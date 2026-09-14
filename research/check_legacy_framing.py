"""Offline diagnostic of published older EPOC AES keys. Not an EEG decoder.

Score repeated counter increments across notifications at all first-block byte
positions and ciphertext offsets. A high score is only a lead, never validation.
"""
import argparse
import json
from collections import Counter, defaultdict
from pathlib import Path
from Crypto.Cipher import AES

def keys(serial):
    # Last-four-byte serial layouts used by public legacy drivers.
    variants = {'raw': bytes.fromhex(serial), 'ascii': serial.encode()}
    variants['raw-reversed'] = variants['raw'][::-1]
    for name, sn in variants.items():
        a,b,c,d = sn[-1],sn[-2],sn[-3],sn[-4]
        layouts = {
            'epoc-research': [a,0,b,84,c,16,d,66,a,0,b,72,c,0,d,80],
            'epoc-consumer': [a,0,b,72,c,0,d,84,a,16,b,66,c,0,d,80],
            'plus-premium': [b,a,b,a,c,d,c,d,d,c,d,c,a,b,a,b],
            'plus-consumer': [a,b,b,c,c,c,b,d,a,d,b,b,d,d,b,a],
            'plus-standard': [a,0,b,21,c,0,d,12,c,0,b,68,a,0,b,88],
        }
        for layout, values in layouts.items():
            yield name+'/'+layout, bytes(values)

def inspect(packets, serial):
    groups = defaultdict(list)
    for p in packets:
        data = bytes.fromhex(p['hex'])
        groups[(p['uuid'],len(data))].append(data)
    scores=[]
    for (uuid, size), payloads in groups.items():
        if len(payloads)<20: continue
        for label, key in keys(serial):
            cipher=AES.new(key,AES.MODE_ECB)
            for offset in range(min(16,size-15)):
                decoded=[cipher.decrypt(b[offset:offset+16]) for b in payloads]
                for position in range(16):
                    for modulus in [128,256]:
                        values=[b[position]%modulus for b in decoded]
                        delta=Counter((y-x)%modulus for x,y in zip(values,values[1:]))
                        # Ignore zero: constant/padding bytes are not sample counters.
                        delta.pop(0,None)
                        step,n=delta.most_common(1)[0] if delta else (None,0)
                        scores.append({'key_layout':label,'payload_bytes':size,
                            'ciphertext_offset':offset,'counter_position':position,
                            'modulus':modulus,'dominant_step':step,
                            'consistent_transition_fraction':n/(len(values)-1)})
    scores.sort(key=lambda s:s['consistent_transition_fraction'],reverse=True)
    return {'decoded':False,'method':'legacy AES ECB first-block counter hypothesis screening',
            'hypotheses_checked':len(scores),'top_candidates':scores[:10],
            'limitation':'Only tests published legacy layouts and simple counters; does not identify modern encryption or validate EEG.'}

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('capture');p.add_argument('--serial',required=True);p.add_argument('--output',required=True)
    a=p.parse_args()
    r=inspect(json.loads(Path(a.capture).read_text())['packets'],a.serial)
    Path(a.output).write_text(json.dumps(r,indent=2)+'\n')
    print(json.dumps({'hypotheses_checked':r['hypotheses_checked'],'best':r['top_candidates'][:1],'decoded':False}))
