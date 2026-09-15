"""Synthetic independent NumPy quantile check; no headset or physiological data."""
import json
import numpy as np

state = 42
mask = (1 << 64) - 1
rows = [(1, 2), (2, 8), (7, 10), (18, 20)]
values = []
for _ in range(1000):
    observed = scored = 0
    for _ in rows:
        state = (state + 0x9e3779b97f4a7c15) & mask
        value = state
        value = ((value ^ (value >> 30)) * 0xbf58476d1ce4e5b9) & mask
        value = ((value ^ (value >> 27)) * 0x94d049bb133111eb) & mask
        value ^= value >> 31
        # Four clusters: 2**64 is divisible by four; no rejection is needed.
        a, b = rows[value % 4]
        observed += a
        scored += b
    values.append(observed / scored)
low, high = np.quantile(values, [0.025, 0.975], method='linear')
assert abs(low - 0.3) < 1e-12 and abs(high - 61 / 70) < 1e-12
print(json.dumps({'synthetic': True, 'seed': 42, 'iterations': 1000,
                  'lower': low, 'upper': high, 'numpy_version': np.__version__}))
