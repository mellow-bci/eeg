"""One EPOC X acquisition pipeline for live BLE and recorded-packet replay.

Writes append-only JSONL with source metadata, original packets, decoded ADC
samples, auxiliary records and errors. Never emits user-intent or action events.
"""
import argparse
import asyncio
import json
import math
import os
import time
from datetime import datetime, timezone
from pathlib import Path
from decoder import (Decoder, ProtocolError, DATA_CHARACTERISTIC,
                     SERIAL_CHARACTERISTIC, REVISION_CHARACTERISTIC, CONFIG_CHARACTERISTIC)


class AcquisitionFailure(RuntimeError):
    """Fatal storage/consumer failure; retrying Bluetooth cannot repair it."""


class Pipeline:
    def __init__(self, output, sample_sink=None, max_bytes=512*1024*1024):
        if not isinstance(max_bytes, int) or max_bytes <= 0:
            raise ValueError('max_bytes must be a positive integer')
        self.max_bytes = max_bytes
        self.bytes_written = 0
        self.file = os.fdopen(os.open(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w')
        self.clock_origin = time.monotonic()
        self.fatal_error = None
        self.sample_sink = sample_sink
        self.stable_segment = 0
        self.decoder = None
        self.packets = self.samples = self.errors = self.auxiliary = 0
        self.discontinuities = 0
        self.first_time = self.last_time = None
        self.epoch = 0
        self.epochs = []
        self.last_packet_at = None
        self.stale_reported = False
        self.stable_since = None
        self.contiguous_samples = 0
        self.transport_stable = False
        self.connection_errors = 0
        self.transport_interruptions = 0

    def write(self, value):
        try:
            line = json.dumps(value, separators=(',', ':'), allow_nan=False) + '\n'
            size = len(line.encode('utf-8'))
            if self.bytes_written+size > self.max_bytes:
                self.fatal_error = 'capture_size_limit'
                self.transport_stable = False
                raise AcquisitionFailure('Capture size limit reached; refusing to silently drop data')
            self.file.write(line)
            self.file.flush()
            self.bytes_written += size
        except (OSError, ValueError) as exc:
            self.fatal_error = 'capture_storage_failed'
            self.transport_stable = False
            raise AcquisitionFailure('Capture storage failed') from exc

    def configure(self, info, source, device=None):
        # Reconnect establishes a new counter epoch, preserving the boundary.
        self.decoder = Decoder(info)
        self.epoch += 1
        self.epochs.append({'epoch': self.epoch, 'samples': 0, 'first_time': None,
                            'last_time': None, 'decode_errors': 0, 'counter_discontinuities': 0,
                            'stable_samples': 0})
        self.last_packet_at = None
        self.stale_reported = False
        self.stable_since = None
        self.contiguous_samples = 0
        self.transport_stable = False
        self.write({'kind': 'stream_start', 'source': source, 'device': device,
                    'epoch': self.epoch,
                    'time': datetime.now(timezone.utc).isoformat(), 'info': info,
                    'sample_units': 'unsigned_adc_counts', 'physiology_validated': False})

    def reset_stability(self, timestamp, reason):
        self.stable_since = None
        self.contiguous_samples = 0
        self.transport_stable = False
        self.write({'kind': 'transport_status', 'status': 'recovering',
                    'epoch': self.epoch, 't': timestamp, 'reason': reason})

    def check_freshness(self, timestamp):
        """Invalidate delivery readiness while silent, not only on the next packet."""
        if (self.last_packet_at is not None and not self.stale_reported
                and timestamp-self.last_packet_at > 0.5):
            self.stale_reported = True
            self.reset_stability(timestamp, 'stale_input')

    def packet(self, packet):
        self.write(dict(packet, kind='ble_notification', epoch=self.epoch))
        if packet['uuid'].lower() != DATA_CHARACTERISTIC:
            return
        self.packets += 1
        timestamp = packet['t']
        if not isinstance(timestamp, (int, float)) or not math.isfinite(timestamp):
            raise AcquisitionFailure('Non-finite packet arrival timestamp')
        if self.last_packet_at is not None:
            if timestamp < self.last_packet_at:
                raise AcquisitionFailure('Packet arrival clock moved backwards')
            if timestamp - self.last_packet_at > 0.5:
                self.reset_stability(timestamp, 'arrival_gap')
        self.last_packet_at = timestamp
        self.stale_reported = False
        try:
            samples, auxiliary = self.decoder.decode(bytes.fromhex(packet['hex']), packet['t'])
        except (ProtocolError, ValueError) as exc:
            self.errors += 1
            self.epochs[-1]['decode_errors'] += 1
            self.write({'kind': 'decode_error', 'epoch': self.epoch,
                        'message': str(exc), 't': packet['t']})
            self.reset_stability(packet['t'], 'rejected_packet')
            return
        if any(not sample['continuous'] for sample in samples):
            self.reset_stability(packet['t'], 'counter_discontinuity')
        elif self.stable_since is None:
            self.stable_since = packet['t']
        else:
            self.contiguous_samples += len(samples)
            if (not self.transport_stable and self.contiguous_samples >= 256
                    and packet['t'] - self.stable_since >= 2):
                self.transport_stable = True
                self.stable_segment += 1
                self.write({'kind': 'transport_status', 'status': 'stable',
                            'epoch': self.epoch, 't': packet['t'],
                            'basis': 'two_seconds_of_contiguous_sample_counters',
                            'physiology_validated': False})
        for sample in samples:
            sample.update(epoch=self.epoch, stream_index=self.samples)
            sample['transport_stable'] = self.transport_stable
            sample['consumer_eligible'] = self.transport_stable and self.decoder.voltage_divisor is not None
            sample['stable_segment'] = self.stable_segment if self.transport_stable else None
            self.write(sample)
            if sample['consumer_eligible'] and self.sample_sink is not None:
                # The consumer receives only stable samples. Segment boundaries
                # prevent joining data across gaps or reconnects. Raw stays intact.
                import copy
                try:
                    self.sample_sink(copy.deepcopy(sample))
                except Exception as exc:
                    self.fatal_error = 'sample_consumer_failed'
                    self.reset_stability(packet['t'], 'consumer_failure')
                    raise AcquisitionFailure('Sample consumer failed') from exc
            self.samples += 1
            self.epochs[-1]['stable_samples'] += bool(self.transport_stable)
            self.discontinuities += not sample['continuous']
            self.epochs[-1]['counter_discontinuities'] += not sample['continuous']
        if self.first_time is None:
            self.first_time = packet['t']
        self.last_time = packet['t']
        current_epoch = self.epochs[-1]
        current_epoch['samples'] += len(samples)
        if current_epoch['first_time'] is None:
            current_epoch['first_time'] = packet['t']
        current_epoch['last_time'] = packet['t']
        if auxiliary:
            auxiliary['epoch'] = self.epoch
            self.write(auxiliary)
            self.auxiliary += 1

    def finish(self):
        duration = (self.last_time - self.first_time
                    if self.first_time is not None else 0)
        summary = {'kind': 'summary', 'packets': self.packets, 'samples': self.samples,
                   'connection_epochs': self.epochs,
                   'auxiliary_records': self.auxiliary, 'decode_errors': self.errors,
                   'counter_discontinuities': self.discontinuities,
                   'arrival_span_seconds': duration,
                   'observed_samples_per_second': (self.samples - 2) / duration if duration > 0 else None,
                   'physiology_validated': False}
        # Overall elapsed time includes reconnect outages; report rates per epoch
        # and avoid presenting that overall value as the device sampling rate.
        for epoch in self.epochs:
            span = ((epoch['last_time'] - epoch['first_time'])
                    if epoch['first_time'] is not None else 0)
            epoch['observed_samples_per_second'] = ((epoch['samples'] - 2) / span
                                                     if span > 0 else None)
        if len(self.epochs) != 1:
            summary['observed_samples_per_second'] = None
        summary['transport_stable_at_end'] = self.transport_stable
        summary['stable_samples'] = sum(epoch['stable_samples'] for epoch in self.epochs)
        summary['connection_errors'] = self.connection_errors
        summary['transport_interruptions'] = self.transport_interruptions
        summary['fatal_error'] = self.fatal_error
        summary['capture_clean'] = bool(self.samples and not self.fatal_error and not self.errors and not self.discontinuities
                                       and not self.connection_errors and not self.transport_interruptions)
        try:
            self.write(summary)
            os.fsync(self.file.fileno())
        finally:
            self.file.close()
        return summary


def connected_device(address):
    """Resolve an already connected macOS peripheral before advertisement lookup."""
    target = address
    import sys
    if sys.platform == 'darwin':
        from bleak.backends.corebluetooth.CentralManagerDelegate import CentralManagerDelegate
        from bleak.backends.device import BLEDevice
        from CoreBluetooth import CBUUID
        manager = CentralManagerDelegate.alloc().init()
        peripherals = manager.central_manager.retrieveConnectedPeripheralsWithServices_(
            [CBUUID.UUIDWithString_('81072f40-9f3d-11e3-a9dc-0002a5d5c51b')])
        for peripheral in peripherals:
            candidate_address = str(peripheral.identifier().UUIDString())
            if candidate_address.upper() == address.upper():
                target = BLEDevice(candidate_address, str(peripheral.name()), (peripheral, manager))
                break
    return target


async def live(args, pipeline):
    from bleak import BleakClient, BleakScanner
    start = pipeline.clock_origin
    for attempt in range(args.attempts):
        pipeline.write({'kind': 'connection_attempt', 'attempt': attempt + 1})
        try:
            if args.device:
                target = connected_device(args.device)
            else:
                target = await BleakScanner.find_device_by_filter(
                    lambda d, a: 'EPOCX' in (a.local_name or d.name or '').upper(), timeout=12)
            if target is None:
                pipeline.write({'kind': 'connection_status', 'status': 'not_found'})
            else:
                disconnected = asyncio.Event()
                async with BleakClient(target, timeout=15,
                                       disconnected_callback=lambda _: disconnected.set()) as client:
                    info = {}
                    for uuid in (SERIAL_CHARACTERISTIC, REVISION_CHARACTERISTIC):
                        info[uuid] = bytes(await client.read_gatt_char(uuid)).hex()
                    # Official configuration payload. Preserve it without assuming
                    # resolution/scaling; failure must not block raw acquisition.
                    try:
                        config = await asyncio.wait_for(
                            client.read_gatt_char(CONFIG_CHARACTERISTIC), timeout=5)
                        info[CONFIG_CHARACTERISTIC] = bytes(config).hex()
                    except Exception as exc:
                        pipeline.write({'kind': 'metadata_read_error',
                                        'uuid': CONFIG_CHARACTERISTIC,
                                        'attempt': attempt + 1, 'message': str(exc)})
                    pipeline.configure(info, 'live_ble', str(client.address))
                    last_notification = time.monotonic()
                    callback_failure = None
                    def notification(characteristic, data):
                        nonlocal last_notification, callback_failure
                        if callback_failure is not None:
                            return
                        last_notification = time.monotonic()
                        try:
                            pipeline.packet({'t': time.monotonic() - start,
                                             'uuid': characteristic.uuid, 'hex': bytes(data).hex()})
                        except Exception as exc:
                            pipeline.fatal_error = 'notification_processing_failed'
                            pipeline.transport_stable = False
                            callback_failure = exc
                    await client.start_notify(DATA_CHARACTERISTIC, notification)
                    deadline = time.monotonic() + args.seconds
                    while time.monotonic() < deadline:
                        if callback_failure is not None:
                            raise AcquisitionFailure('Notification processing failed') from callback_failure
                        pipeline.check_freshness(time.monotonic()-start)
                        try:
                            await asyncio.wait_for(disconnected.wait(),
                                timeout=min(0.1, max(0.001, deadline - time.monotonic())))
                            pipeline.write({'kind': 'connection_status', 'status': 'disconnected'})
                            pipeline.transport_interruptions += 1
                            pipeline.reset_stability(time.monotonic() - start, 'disconnected')
                            break
                        except asyncio.TimeoutError:
                            if time.monotonic() - last_notification > 5:
                                pipeline.transport_interruptions += 1
                                pipeline.reset_stability(time.monotonic() - start, 'notification_timeout')
                                raise TimeoutError('No EEG notifications for five seconds')
                    else:
                        if callback_failure is not None:
                            raise AcquisitionFailure('Notification processing failed') from callback_failure
                        return
        except AcquisitionFailure:
            raise
        except Exception as exc:
            pipeline.connection_errors += 1
            pipeline.write({'kind': 'connection_error', 'message': str(exc)})
        if attempt + 1 < args.attempts:
            await asyncio.sleep(min(2 ** attempt, 10))



class DeviceLease:
    """Prevent two instances of this reader from acquiring the same device."""
    def __init__(self, device, directory=None):
        import tempfile, hashlib
        self.directory = Path(directory or (Path(tempfile.gettempdir()) / ('chorus-epoc-'+str(os.getuid()))))
        self.directory.mkdir(mode=0o700, exist_ok=True)
        self.path = self.directory / (hashlib.sha256((device or 'discovery').upper().encode()).hexdigest()+'.lock')
        self.handle = None
    def __enter__(self):
        import fcntl
        self.handle = os.fdopen(os.open(self.path, os.O_RDWR | os.O_CREAT, 0o600), 'r+')
        try:
            fcntl.flock(self.handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            self.handle.close()
            raise AcquisitionFailure('Another reader already owns this device')
        return self
    def __exit__(self, *args):
        self.handle.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--replay', help='Saved capture JSON; otherwise capture live BLE')
    parser.add_argument('--output', required=True, help='New JSONL file; existing files are never overwritten')
    parser.add_argument('--device', help='Optional CoreBluetooth identifier for a previously discovered headset')
    parser.add_argument('--seconds', type=float, default=30)
    parser.add_argument('--max-bytes', type=int, default=512*1024*1024, help='Hard recording size budget; exceeding it fails capture')
    parser.add_argument('--attempts', type=int, default=3)
    parser.add_argument('--cycles', type=int, default=1,
                        help='Deliberate disconnect/reconnect capture cycles for validation')
    args = parser.parse_args()
    if not 0 < args.seconds <= 3600 or not 1 <= args.attempts <= 10 or not 1 <= args.cycles <= 10:
        parser.error('seconds must be 0..3600, attempts and cycles 1..10')
    import signal
    def stop_requested(signum, frame):
        raise KeyboardInterrupt
    previous_sigterm = signal.signal(signal.SIGTERM, stop_requested)
    pipeline = Pipeline(args.output, max_bytes=args.max_bytes)
    try:
        if args.replay:
            capture = json.loads(Path(args.replay).read_text())
            pipeline.configure(capture['info'], 'recorded_ble_replay', capture.get('address'))
            for packet in capture['packets']:
                pipeline.packet(packet)
        else:
            async def capture_cycles():
                for cycle in range(args.cycles):
                    pipeline.write({'kind': 'capture_cycle', 'cycle': cycle + 1})
                    await live(args, pipeline)
                    if cycle + 1 < args.cycles:
                        await asyncio.sleep(2)
            with DeviceLease(args.device):
                asyncio.run(capture_cycles())
    except KeyboardInterrupt:
        pipeline.reset_stability(time.monotonic()-pipeline.clock_origin, 'operator_stop')
        pipeline.write({'kind':'shutdown','reason':'operator_stop'})
    except AcquisitionFailure:
        pipeline.fatal_error = pipeline.fatal_error or 'acquisition_failed'
        pipeline.transport_stable = False
        raise
    finally:
        signal.signal(signal.SIGTERM, previous_sigterm)
        summary = pipeline.finish()
        print(json.dumps(summary))
    return 0 if summary['capture_clean'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
