"""Replay existing decoded capture into a separate CQ research report."""
import argparse,json
from pathlib import Path
from collections import defaultdict
from contact_quality import ContactQuality
p=argparse.ArgumentParser();p.add_argument('capture');p.add_argument('--output',required=True);args=p.parse_args()
tracker=None;counts=defaultdict(list);updates=0
with Path(args.output).open('x') as out:
 for line in Path(args.capture).open():
  row=json.loads(line)
  if row['kind']=='stream_start':tracker=ContactQuality(row['info'])
  elif row['kind']=='eeg_adc' and tracker:
   event=tracker.update(row)
   if event:
    event['epoch']=row.get('epoch');out.write(json.dumps(event)+'\n')
    counts[event['slot']].append(event['raw_value']);updates+=1
summary={'raw_updates':updates,'slots':{k:{'count':len(v),'min':min(v),'max':max(v)} for k,v in counts.items()},'reference_validated':False}
print(json.dumps(summary))
