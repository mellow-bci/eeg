"""Descriptive signal checks, not contact scoring or physiological diagnosis."""
import argparse,json
from pathlib import Path
import numpy as np
from scipy.signal import welch

def analyze(path):
    rows=[json.loads(line) for line in Path(path).read_text().splitlines()]
    segments=[]; current=[]
    for row in rows:
        if row['kind']=='eeg_adc' and row.get('transport_stable') and row.get('continuous'):
            if current and row['epoch']!=current[-1]['epoch']:
                segments.append(current);current=[]
            current.append(row)
        elif row['kind'] in ('eeg_adc','decode_error','stream_start'):
            if current: segments.append(current);current=[]
    if current:segments.append(current)
    segment=max(segments,key=len,default=[])
    result={'source':str(path),'analysis':'longest_contiguous_transport_stable_segment',
            'samples':len(segment),'assumed_sample_rate_hz':128,
            'physiology_validated':False,'contact_quality_verified':False}
    if len(segment)<256:return result
    channels={}
    for name in segment[0]['electrodes_adc']:
        raw=np.array([s['electrodes_adc'][name] for s in segment],dtype=float)
        ch={'adc_min':float(raw.min()),'adc_max':float(raw.max()),
            'rail_fraction':float(np.mean((raw==0)|(raw==65535))),
            'unchanged_step_fraction':float(np.mean(np.diff(raw)==0))}
        if all('electrodes_microvolts' in s for s in segment):
            x=np.array([s['electrodes_microvolts'][name] for s in segment])
            f,p=welch(x,fs=128,nperseg=min(512,len(x)),detrend='linear')
            def power(lo,hi):return float(np.sum(p[(f>=lo)&(f<hi)])*(f[1]-f[0]))
            ch.update(voltage_basis='vendor_scaled_uncentered',
                      ac_rms_microvolts=float(np.std(x)),
                      p99_step_microvolts=float(np.percentile(abs(np.diff(x)),99)),
                      power_1_40_uV2=power(1,40),power_8_13_uV2=power(8,13),
                      power_49_51_uV2=power(49,51),power_59_61_uV2=power(59,61))
        channels[name]=ch
    result.update(segment_first_host_time=segment[0]['received_at'],
                  segment_last_host_time=segment[-1]['received_at'],channels=channels)
    return result

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('capture');p.add_argument('--output',required=True)
    a=p.parse_args();result=analyze(a.capture)
    with Path(a.output).open('x') as f:json.dump(result,f,indent=2)
    print(json.dumps(result))
