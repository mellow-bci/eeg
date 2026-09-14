"""Explicit adapters into immutable EEG samples; no resampling or inferred intent."""
from dataclasses import dataclass
import hashlib
import json
import math
from pathlib import Path
from typing import Optional, Tuple

CHANNELS = ('AF3','F7','F3','FC5','T7','P7','O1','O2','P8','T8','FC6','F4','F8','AF4')
CONTRACT_VERSION = 'eeg.canonical.v2'
SUPPORTED_CONFIG = '018000102010'
CONFIG_UUID = '81072f44-9f3d-11e3-a9dc-0002a5d5c51b'
MAX_LINE = 4 * 1024 * 1024
ELECTRODE_WORDS = (2,3,0,1,4,5,6,8,9,10,13,14,11,12)

@dataclass(frozen=True)
class CanonicalSample:
    index: int
    counter: int
    received_at: float
    epoch: Optional[int]
    stable_segment: Optional[int]
    transport_stable: bool
    continuous: bool
    adc: Tuple[float, ...]
    microvolts: Optional[Tuple[float, ...]]
    config_id: Optional[str]
    source_id: str

    def __post_init__(self):
        _integer(self.index,'index');_integer(self.counter,'counter')
        if self.counter >= 128:raise ValueError('Counter exceeds observed range')
        _number(self.received_at)
        if self.received_at < 0:raise ValueError('Arrival timestamp must be nonnegative')
        _integer(self.epoch,'epoch',True);_integer(self.stable_segment,'stable_segment',True)
        if type(self.transport_stable) is not bool or type(self.continuous) is not bool:
            raise ValueError('Transport and continuity flags must be booleans')
        if self.config_id is not None and (not isinstance(self.config_id,str) or not self.config_id):
            raise ValueError('Configuration identity must be nonempty text or unknown')
        if not isinstance(self.source_id,str) or not self.source_id:raise ValueError('Source identity is required')
        for vector in (self.adc,self.microvolts):
            if vector is not None:
                if not isinstance(vector,tuple) or len(vector)!=14:raise ValueError('Immutable fourteen-channel tuple required')
                for value in vector:_number(value)
        if not isinstance(self.adc,tuple) or any(a<0 or a>65535 or a!=int(a) for a in self.adc):
            raise ValueError('ADC counts must be unsigned integers')
        if self.microvolts is not None and self.config_id==SUPPORTED_CONFIG and any(abs(v-a/7.8)>1e-6 for a,v in zip(self.adc,self.microvolts)):
            raise ValueError('Voltage does not match observed ADC conversion')


def _integer(value, name, nullable=False):
    if nullable and value is None: return None
    if type(value) is not int or value < 0: raise ValueError('Invalid '+name)
    return value


def _number(value):
    if isinstance(value, bool) or not isinstance(value, (float,int)) or not math.isfinite(value):
        raise ValueError('Sample numeric values must be finite')
    return float(value)


def _vector(values):
    if not isinstance(values,dict) or any(c not in values for c in CHANNELS):
        raise ValueError('All fourteen named EEG channels are required')
    return tuple(_number(values[c]) for c in CHANNELS)


def _config(info):
    if not isinstance(info,dict): raise ValueError('Invalid device metadata')
    normalized={str(k).lower():v for k,v in info.items()}
    value=normalized.get(CONFIG_UUID)
    if value is None:return None
    if not isinstance(value,str):raise ValueError('Configuration must be hexadecimal text')
    return value.lower()


def iter_event_samples(events, source_id, require_complete=False):
    """Same adapter for live event iterators and file readers. Live need not finish.

    Native status is reconstructed only from explicit chronological transport events;
    absence of status is never treated as stable. A native start defines one epoch.
    """
    if not isinstance(source_id,str) or not source_id:raise ValueError('Source identity is required')
    mode=None;config=None;stable=False;segment=0;epoch=None;started=False;final=False;sample_count=0
    for event in events:
        if not isinstance(event,dict):raise ValueError('Event must be an object')
        kind=event.get('kind')
        if not isinstance(kind,str):raise ValueError('Event kind is required')
        if final:raise ValueError('Events after final summary')
        if kind=='stream_start':
            schema=event.get('schema')
            if schema is None:
                if mode=='native':raise ValueError('Mixed recording schemas')
                mode='python';config=_config(event.get('info',{}));epoch=_integer(event.get('epoch'),'epoch',True)
            elif schema=='eeg-native-v1':
                if started:raise ValueError('Repeated native stream start')
                mode='native';config=None;epoch=1
            else:raise ValueError('Unsupported recording schema')
            started=True;stable=False;segment=0
            continue
        if not started:
            if kind not in ('eeg_adc','eeg_sample','summary'):continue
            raise ValueError('EEG or summary precedes stream metadata')
        if kind=='summary':
            if type(event.get('samples')) is not int or event['samples']!=sample_count:raise ValueError('Summary sample count mismatch')
            final=True;continue
        if kind=='import_failed':raise ValueError('Failed imported recording')
        if kind=='device_metadata' and mode=='native':
            info=event
            if 'metadata_json' in event:
                info=json.loads(event['metadata_json'])
            config=_config(info);continue
        if kind=='transport_status' and mode=='native':
            status=event.get('status')
            if status not in ('stable','recovering'):raise ValueError('Unsupported transport status')
            next_stable=status=='stable'
            if next_stable and not stable:segment+=1
            stable=next_stable;continue
        if kind in ('decode_error','connection_error') and mode=='native':stable=False
        if kind not in ('eeg_adc','eeg_sample'):continue
        if mode=='python':
            if kind!='eeg_adc' or event.get('units')!='unsigned_adc_counts':raise ValueError('Unsupported Python sample units/schema')
            sample=event;index=sample.get('stream_index',sample.get('index'))
            at=sample.get('received_at');adc=_vector(sample.get('electrodes_adc'))
            volts=sample.get('electrodes_microvolts')
            sample_epoch=_integer(sample.get('epoch',epoch),'epoch',True)
            sample_segment=_integer(sample.get('stable_segment'),'stable_segment',True)
            sample_stable=sample.get('transport_stable') is True
        else:
            if kind!='eeg_sample' or not isinstance(event.get('sample'),dict):raise ValueError('Unsupported native sample schema')
            sample=event['sample'];index=sample.get('index');at=sample.get('receivedAt')
            words=sample.get('adcWords')
            if not isinstance(words,list) or len(words)!=15:raise ValueError('Native ADC word count must be fifteen')
            adc=_vector(sample.get('electrodesADC'));volts=sample.get('electrodesMicrovolts')
            sample_epoch=epoch;sample_segment=segment if stable else None;sample_stable=stable
        index=_integer(index,'index');counter=_integer(sample.get('counter'),'counter')
        if counter>=128:raise ValueError('Counter exceeds observed range')
        words=sample.get('adcWords') if mode=='native' else sample.get('adc_words')
        if words is not None:
            if not isinstance(words,list) or len(words)!=15 or any(type(v) is not int or not 0<=v<=65535 for v in words):
                raise ValueError('Invalid ADC words')
            if adc!=tuple(float(words[i]) for i in ELECTRODE_WORDS):raise ValueError('ADC channel map differs from wire words')
        if any(a<0 or a>65535 or a!=int(a) for a in adc):raise ValueError('ADC counts must be unsigned integers')
        calibrated=None if volts is None else _vector(volts)
        if calibrated is not None and config==SUPPORTED_CONFIG and any(abs(v-a/7.8)>1e-6 for a,v in zip(adc,calibrated)):
            raise ValueError('Voltage does not match observed ADC conversion')
        sample_count+=1
        yield CanonicalSample(index,counter,_number(at),sample_epoch,sample_segment,
                              sample_stable,sample.get('continuous') is True,adc,calibrated,config,source_id)
    if require_complete and not final:raise ValueError('Recording has no final summary')


def _events(path):
    with Path(path).open('rb') as stream:
        for line in iter(lambda:stream.readline(MAX_LINE+1),b''):
            if len(line)>MAX_LINE:raise ValueError('Recording line exceeds limit')
            if not line.endswith(b'\n'):raise ValueError('Partial recording line')
            yield json.loads(line,parse_constant=lambda value: (_ for _ in ()).throw(ValueError('Non-finite JSON')))


def iter_samples(path):
    """File source identity is SHA-256; readers keep bounded line memory."""
    path=Path(path);digest=hashlib.sha256()
    before=path.stat()
    with path.open('rb') as stream:
        for chunk in iter(lambda:stream.read(1024*1024),b''):digest.update(chunk)
    yield from iter_event_samples(_events(path),digest.hexdigest(),require_complete=True)
    after=path.stat()
    if (before.st_size,before.st_mtime_ns)!=(after.st_size,after.st_mtime_ns):
        raise ValueError('Recording changed during processing')
