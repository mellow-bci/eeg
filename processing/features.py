"""Independent spectral feature design v1; not recovered Cortex parameters."""
import hashlib,json
import numpy as np
from scipy.signal import detrend,welch
from processing.contract import CHANNELS
BANDS=((1,4),(4,8),(8,13),(13,30),(30,40))
CONFIG={'version':'eeg.features.v1','source':'independent_design','sample_rate':128,'window_samples':256,
        'overlap':0,'channels':CHANNELS,'bands_hz':BANDS,'welch_window':'hann','nperseg':256,'noverlap':0,
        'detrend':'linear','feature':'log10_integrated_power_uV2','power_floor':1e-12,
        'artifact_peak_to_peak_uV':500,'artifact_rms_uV':100,
        'artifact_thresholds_validated':False,'mental_task_validated':False}
CONFIG_ID=hashlib.sha256(json.dumps(CONFIG,sort_keys=True).encode()).hexdigest()
NAMES=tuple(f'{c}.logpower.{lo}-{hi}Hz' for c in CHANNELS for lo,hi in BANDS)

def extract_matrix(values):
    """values is256x14 uncentered observed-config uV; raw input never mutated."""
    x=np.asarray(values,dtype=float)
    if x.shape!=(256,14) or not np.isfinite(x).all():raise ValueError('Require256 finite samples for all14 channels')
    if np.any((x<=0)|(x>=65535/7.8)):raise ValueError('ADC rail clipping or invalid voltage')
    centered=detrend(x,axis=0,type='linear');rms=np.sqrt(np.mean(centered**2,axis=0));ptp=np.ptp(centered,axis=0)
    flags=[]
    if np.any(ptp>CONFIG['artifact_peak_to_peak_uV']):flags.append('high_amplitude_artifact_possible')
    if np.any(rms>CONFIG['artifact_rms_uV']):flags.append('high_rms_artifact_possible')
    if np.any(rms<1e-8):flags.append('flat_channel')
    f,psd=welch(x,fs=128,window='hann',nperseg=256,noverlap=0,detrend='linear',axis=0,scaling='density')
    vector=[]
    for ch in range(14):
        for lo,hi in BANDS:
            power=float(psd[(f>=lo)&(f<hi),ch].sum()*(f[1]-f[0]));vector.append(float(np.log10(max(power,CONFIG['power_floor']))))
    return {'feature_version':CONFIG['version'],'feature_config_id':CONFIG_ID,'values':vector,'artifact_flags':flags,
            'artifact_indicators':{'detrended_rms_uV':dict(zip(CHANNELS,rms.tolist())),
                                   'detrended_peak_to_peak_uV':dict(zip(CHANNELS,ptp.tolist()))},
            'usable':not flags,'cognitive_interpretation':None}
