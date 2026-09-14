"""Record an operator cue; does not claim measured participant compliance."""
import json,sys
from pathlib import Path
from datetime import datetime,timezone
p=Path(sys.argv[1]);rows=[json.loads(x) for x in p.read_text().splitlines()]
t=next(r['received_at'] for r in reversed(rows) if r['kind']=='eeg_adc')
marker={'phase':sys.argv[2],'latest_sample_host_time':t,'cue_logged_utc':datetime.now(timezone.utc).isoformat(),'timing_basis':'operator_cue_near_latest_notification','participant_compliance_verified':False}
with p.with_suffix('.markers.jsonl').open('a') as f:f.write(json.dumps(marker)+'\n')
print(marker)
