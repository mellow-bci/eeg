"""Versioned supported tuning; hardware/feature recipe remains independently gated."""
import copy
import json
import math
from pathlib import Path

DEFAULTS = {'schema':'eeg.processing-settings.v1', 'max_training_windows':None,
            'selected_features':20, 'pca_components':8, 'variance_floor':.05,
            'score_threshold':.9, 'margin_threshold':.25, 'persistence_windows':2}
ALGORITHM_KEYS = ('selected_features','pca_components','variance_floor',
                  'score_threshold','margin_threshold','persistence_windows')


def validate_settings(value=None):
    result=copy.deepcopy(DEFAULTS)
    if value is not None:
        if not isinstance(value,dict) or set(value)-set(DEFAULTS):
            raise ValueError('Unknown processing settings')
        result.update(value)
    if result['schema']!=DEFAULTS['schema']:raise ValueError('Unsupported settings schema')
    for key in ('selected_features','pca_components','persistence_windows'):
        if type(result[key]) is not int or result[key]<1:raise ValueError('Invalid '+key)
    if result['selected_features']>70 or result['pca_components']>result['selected_features']:
        raise ValueError('Dimensions exceed current feature recipe')
    budget=result['max_training_windows']
    if budget is not None and (type(budget) is not int or budget<1):raise ValueError('Invalid optional training budget')
    for key in ('variance_floor','score_threshold','margin_threshold'):
        v=result[key]
        if type(v) not in (int,float) or not math.isfinite(v):raise ValueError('Invalid '+key)
    if result['variance_floor']<=0 or not 0<result['score_threshold']<=1 or not 0<=result['margin_threshold']<=1:
        raise ValueError('Invalid variance or score threshold')
    return result


def load_settings(path):
    return validate_settings(json.loads(Path(path).read_text()))
