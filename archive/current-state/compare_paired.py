"""Compare direct EEG with Cortex using full ADC vectors plus counters.

A match requires every electrode, not just a wrapping sample counter. Ambiguous
matches remain unverified. This validates samples, not physiological quality.
"""
import argparse, hashlib, json
from collections import defaultdict
from pathlib import Path
import numpy as np
import pyarrow.parquet as pq
from decoder import ELECTRODE_WORDS

def compare(raw, reference):
    raw,reference=Path(raw),Path(reference)
    samples=[];summary=None;starts=[]
    with raw.open() as f:
        for line in f:
            r=json.loads(line)
            if r.get('kind')=='eeg_adc':samples.append(r)
            elif r.get('kind')=='summary':summary=r
            elif r.get('kind')=='stream_start':starts.append(r)
    if not samples or summary is None:raise ValueError('Complete nonempty direct capture required')
    if any('electrodes_microvolts' not in r for r in samples):raise ValueError('Calibrated configuration required')
    names=[n for n,_ in ELECTRODE_WORDS]
    columns=['EEG.'+n for n in names]+['EEG.Counter','Timestamp','EEG.Interpolated']
    schema=pq.read_schema(reference)
    if 'EEG.RawCq' in schema.names:columns.append('EEG.RawCq')
    t=pq.read_table(reference,columns=columns)
    v=np.column_stack([t['EEG.'+n].to_numpy() for n in names]).astype(float)
    counters=t['EEG.Counter'].to_numpy();timestamps=t['Timestamp'].to_numpy()
    valid=np.isfinite(v).all(axis=1)&np.isfinite(counters)&np.isfinite(timestamps)&(t['EEG.Interpolated'].to_numpy()==0)
    adc=np.rint(np.nan_to_num(v)*7.8).astype(np.int64)
    lookup=defaultdict(list)
    for i in np.flatnonzero(valid):lookup[(int(counters[i]),*adc[i].tolist())].append(int(i))
    matched=[];unmatched=[];ambiguous=[];max_error=0.0
    for j,r in enumerate(samples):
        ids=lookup.get((r['counter'],*[r['electrodes_adc'][n] for n in names]),[])
        if len(ids)==1:
            i=ids[0];matched.append((j,i))
            max_error=max(max_error,float(np.max(np.abs(v[i]-[r['electrodes_microvolts'][n] for n in names]))))
        elif ids:ambiguous.append(j)
        else:unmatched.append(j)
    stable_indices={j for j,r in enumerate(samples) if r.get('transport_stable')}
    stable=[(j,i) for j,i in matched if j in stable_indices]
    groups=defaultdict(list)
    for j,i in stable:groups[(samples[j]['epoch'],samples[j].get('stable_segment'))].append((j,i))
    contiguous=bool(stable) and all(all(b[1]==a[1]+1 for a,b in zip(g,g[1:])) for g in groups.values())
    max_residual=float(np.max(np.abs(v[valid]*7.8-adc[valid]))) if np.any(valid) else None
    report={'direct_samples':len(samples),'reference_rows':len(v),
        'unique_full_vector_matches':len(matched),'unmatched_count':len(unmatched),
        'unmatched_indices':unmatched,'ambiguous_count':len(ambiguous),'ambiguous_indices':ambiguous,
        'stable_samples':len(stable_indices),'stable_matches':len(stable),
        'stable_unmatched_indices':sorted(stable_indices-{j for j,i in stable}),
        'stable_reference_contiguous_within_segments':contiguous,
        'stable_full_match':bool(stable_indices) and len(stable)==len(stable_indices) and contiguous,
        'max_voltage_error_uV':max_error if matched else None,'reference_max_adc_grid_residual':max_residual,
        'reference_order_reversals':[{'direct_before':a[0],'direct_after':b[0],'reference_before':a[1],'reference_after':b[1]} for a,b in zip(matched,matched[1:]) if b[1]<=a[1]],
        'first_matched_timestamp':float(timestamps[matched[0][1]]) if matched else None,
        'last_matched_timestamp':float(timestamps[matched[-1][1]]) if matched else None,
        'direct_sha256':hashlib.sha256(raw.read_bytes()).hexdigest(),
        'reference_sha256':hashlib.sha256(reference.read_bytes()).hexdigest(),
        'direct_summary':summary,'stream_identity':starts,
        'method':'counter plus all 14 electrode ADC values; reference voltage rounded at observed 7.8 counts/uV; ambiguous matches rejected',
        'physiology_validated':False,'production_ready':False}
    if 'EEG.RawCq' in columns:
        cq=t['EEG.RawCq'].to_numpy()
        report['matched_raw_cq_equal']=sum(float(cq[i])==samples[j]['other_word_7'] for j,i in matched)
        report['matched_raw_cq_compared']=len(matched)
    return report

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('direct');p.add_argument('reference');p.add_argument('--output',required=True)
    args=p.parse_args();report=compare(args.direct,args.reference)
    with Path(args.output).open('x') as f:json.dump(report,f,indent=2)
    print(json.dumps({k:v for k,v in report.items() if k not in ('stream_identity','direct_summary','unmatched_indices','ambiguous_indices','stable_unmatched_indices')},indent=2))
