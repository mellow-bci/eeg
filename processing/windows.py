"""One nonoverlapping 256-sample, observed-128-Hz window contract."""
from dataclasses import dataclass
from typing import Tuple
from processing.contract import CanonicalSample, SUPPORTED_CONFIG

@dataclass(frozen=True)
class Window:
    samples: Tuple[CanonicalSample, ...]
    valid: bool
    reasons: Tuple[str, ...]
    start: float
    end: float
    id: str


def _window(samples,ordinal,previous=None):
    reasons=[]
    if len(samples)!=256:reasons.append('partial_window')
    if any(not s.transport_stable for s in samples):reasons.append('transport_unstable')
    if any(not s.continuous for s in samples):reasons.append('sample_discontinuity')
    if len({(s.source_id,s.epoch,s.stable_segment) for s in samples})!=1:reasons.append('source_or_segment_boundary')
    if any(s.epoch is None or s.stable_segment is None for s in samples):reasons.append('missing_epoch_or_segment')
    if any(s.config_id!=SUPPORTED_CONFIG for s in samples):reasons.append('unsupported_configuration')
    if any(s.microvolts is None for s in samples):reasons.append('missing_microvolts')
    if any(len(s.adc)!=14 or any(a<0 or a>65535 for a in s.adc) for s in samples):reasons.append('invalid_adc')
    pairs=list(zip(samples,samples[1:]))
    if previous is not None and (previous.source_id,previous.epoch,previous.stable_segment)==(samples[0].source_id,samples[0].epoch,samples[0].stable_segment):
        pairs.insert(0,(previous,samples[0]))
    for a,b in pairs:
        if b.index!=a.index+1 or b.counter!=(a.counter+1)%128:
            if 'index_or_counter_gap' not in reasons:reasons.append('index_or_counter_gap')
        if b.received_at<a.received_at or b.received_at-a.received_at>.5:
            if 'arrival_gap' not in reasons:reasons.append('arrival_gap')
    span=samples[-1].received_at-samples[0].received_at
    if len(samples)>2 and (span<=0 or not 120<=(len(samples)-2)/span<=136):reasons.append('sample_rate_not_observed_128hz')
    return Window(tuple(samples),not reasons,tuple(reasons),samples[0].received_at,
                  samples[-1].received_at,f'{samples[0].source_id}:{ordinal}')


def iter_windows(samples,size=256):
    if type(size) is not int or size!=256:raise ValueError('Only fixed 256-sample nonoverlapping windows are supported')
    buffer=[];ordinal=0;previous=None
    for sample in samples:
        if not isinstance(sample,CanonicalSample):raise ValueError('CanonicalSample required')
        buffer.append(sample)
        if len(buffer)==size:
            yield _window(buffer,ordinal,previous);previous=buffer[-1];buffer=[];ordinal+=1
    if buffer:yield _window(buffer,ordinal,previous)
