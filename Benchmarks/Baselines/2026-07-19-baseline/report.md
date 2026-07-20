# Kvist release performance report

Generated: 2026-07-19T04:03:54.103Z  
Commit: `39bf12189fa86f0d754f42658c0549442f5f665a` (dirty)  
System: Version 27.0 (Build 26A5378j), 12 logical CPUs  
Build: release

Raw machine-readable samples are in [`raw-results.json`](raw-results.json).

## Guardrails

| Status | Repository | Metric | Statistic | Measured | Limit |
| --- | --- | --- | --- | ---: | ---: |
| PASS | All | App bundle | value | 6.024 MiB | ≤ 6.250 MiB |
| PASS | All | Compressed app | value | 1.403 MiB | ≤ 1.500 MiB |
| PASS | GitLite | Launch | median | 216.377 ms | ≤ 300.000 ms |
| PASS | GitLite | Launch | p95 | 233.298 ms | ≤ 400.000 ms |
| PASS | GitLite | Startup peak footprint | maximum | 30.298 MiB | ≤ 180.000 MiB |
| PASS | GitLite | Settled footprint | maximum | 46.938 MiB | ≤ 65.000 MiB |
| PASS | GitLite | Idle CPU | maximum | 0.001 % | ≤ 0.200 % |
| PASS | GitLite | Idle wakeups | maximum | 0.800 /s | ≤ 2.000 /s |
| PASS | GitLite | Working-tree refresh | median | 9.590 ms | ≤ 75.000 ms |
| PASS | GitLite | Working-tree refresh | p95 | 12.655 ms | ≤ 125.000 ms |
| PASS | GitLite | Initial Git loading | median | 63.066 ms | ≤ 90.000 ms |
| PASS | GitLite | Initial Git loading | p95 | 83.157 ms | ≤ 150.000 ms |
| PASS | Paeonia | Launch | median | 217.312 ms | ≤ 300.000 ms |
| PASS | Paeonia | Launch | p95 | 230.915 ms | ≤ 400.000 ms |
| PASS | Paeonia | Startup peak footprint | maximum | 30.267 MiB | ≤ 180.000 MiB |
| PASS | Paeonia | Settled footprint | maximum | 41.938 MiB | ≤ 65.000 MiB |
| PASS | Paeonia | Idle CPU | maximum | 0.001 % | ≤ 0.200 % |
| PASS | Paeonia | Idle wakeups | maximum | 0.900 /s | ≤ 2.000 /s |
| PASS | Paeonia | Working-tree refresh | median | 27.863 ms | ≤ 75.000 ms |
| PASS | Paeonia | Working-tree refresh | p95 | 33.283 ms | ≤ 125.000 ms |
| PASS | Paeonia | Initial Git loading | median | 82.985 ms | ≤ 90.000 ms |
| PASS | Paeonia | Initial Git loading | p95 | 96.978 ms | ≤ 150.000 ms |
| PASS | Tidex | Launch | median | 220.285 ms | ≤ 300.000 ms |
| PASS | Tidex | Launch | p95 | 236.520 ms | ≤ 400.000 ms |
| PASS | Tidex | Startup peak footprint | maximum | 29.501 MiB | ≤ 180.000 MiB |
| PASS | Tidex | Settled footprint | maximum | 42.079 MiB | ≤ 65.000 MiB |
| PASS | Tidex | Idle CPU | maximum | 0.001 % | ≤ 0.200 % |
| PASS | Tidex | Idle wakeups | maximum | 0.999 /s | ≤ 2.000 /s |
| PASS | Tidex | Working-tree refresh | median | 18.863 ms | ≤ 75.000 ms |
| PASS | Tidex | Working-tree refresh | p95 | 29.862 ms | ≤ 125.000 ms |
| PASS | Tidex | Initial Git loading | median | 74.159 ms | ≤ 90.000 ms |
| PASS | Tidex | Initial Git loading | p95 | 113.795 ms | ≤ 150.000 ms |

## Summary

| Repository | Metric | Samples | Median | p95 |
| --- | --- | ---: | ---: | ---: |
| All | App bundle | 1 | 6.024 MiB | 6.024 MiB |
| All | Compressed app | 1 | 1.403 MiB | 1.403 MiB |
| GitLite | Launch to initial frame | 20 | 216.377 ms | 233.298 ms |
| GitLite | Startup peak physical footprint | 20 | 28.852 MiB | 30.095 MiB |
| GitLite | Settled physical footprint | 5 | 46.735 MiB | 46.938 MiB |
| GitLite | Idle CPU | 5 | 0.001 % | 0.001 % |
| GitLite | Idle wakeups | 5 | 0.700 /s | 0.800 /s |
| GitLite | Working-tree refresh | 30 | 9.590 ms | 12.655 ms |
| GitLite | Initial repository loading | 30 | 63.066 ms | 83.157 ms |
| Paeonia | Launch to initial frame | 20 | 217.312 ms | 230.915 ms |
| Paeonia | Startup peak physical footprint | 20 | 28.485 MiB | 29.329 MiB |
| Paeonia | Settled physical footprint | 5 | 41.110 MiB | 41.938 MiB |
| Paeonia | Idle CPU | 5 | 0.001 % | 0.001 % |
| Paeonia | Idle wakeups | 5 | 0.600 /s | 0.900 /s |
| Paeonia | Working-tree refresh | 30 | 27.863 ms | 33.283 ms |
| Paeonia | Initial repository loading | 30 | 82.985 ms | 96.978 ms |
| Tidex | Launch to initial frame | 20 | 220.285 ms | 236.520 ms |
| Tidex | Startup peak physical footprint | 20 | 28.681 MiB | 29.251 MiB |
| Tidex | Settled physical footprint | 5 | 41.798 MiB | 42.079 MiB |
| Tidex | Idle CPU | 5 | 0.001 % | 0.001 % |
| Tidex | Idle wakeups | 5 | 0.800 /s | 0.999 /s |
| Tidex | Working-tree refresh | 30 | 18.863 ms | 29.862 ms |
| Tidex | Initial repository loading | 30 | 74.159 ms | 113.795 ms |

## Raw samples

### GitLite

- Launch to initial frame (ms): 191.810, 200.982, 225.615, 244.241, 214.242, 197.651, 219.325, 219.171, 211.902, 214.870, 217.884, 220.363, 220.130, 222.903, 211.248, 206.585, 228.407, 207.964, 211.588, 233.298

- Startup peak physical footprint (MiB): 28.438, 29.001, 28.907, 30.095, 27.829, 29.923, 27.720, 28.157, 27.407, 29.563, 27.595, 29.001, 28.657, 30.017, 30.298, 27.876, 28.798, 28.188, 29.220, 29.063

- Settled physical footprint (MiB): 46.782, 46.735, 46.938, 46.470, 46.485

- Idle CPU (%): 0.001, 0.001, 0.001, 0.000, 0.001

- Idle wakeups (/s): 0.700, 0.800, 0.800, 0.700, 0.600

- Working-tree refresh (ms): 12.655, 14.269, 10.454, 10.164, 10.444, 10.296, 9.628, 10.100, 9.574, 9.049, 9.002, 8.821, 9.062, 9.483, 10.244, 9.620, 9.720, 9.339, 9.588, 10.347, 8.648, 9.671, 8.855, 8.728, 8.510, 8.770, 9.774, 9.147, 9.592, 9.183

- Initial repository loading (ms): 83.157, 85.358, 69.567, 75.235, 67.072, 66.963, 65.597, 63.629, 62.121, 60.949, 61.300, 60.780, 63.275, 63.012, 62.513, 63.119, 63.659, 63.144, 63.291, 61.437, 60.248, 61.399, 61.313, 59.644, 61.147, 60.634, 63.993, 61.438, 63.346, 60.845

### Paeonia

- Launch to initial frame (ms): 202.653, 230.915, 219.258, 218.534, 210.344, 224.436, 214.105, 216.706, 232.274, 211.357, 211.541, 219.386, 209.673, 217.917, 208.226, 222.301, 202.827, 220.365, 216.188, 220.200

- Startup peak physical footprint (MiB): 30.267, 28.392, 28.126, 28.470, 29.126, 29.329, 28.204, 28.392, 29.251, 28.204, 28.579, 28.501, 28.642, 28.313, 28.298, 27.876, 29.001, 28.423, 28.610, 29.142

- Settled physical footprint (MiB): 41.938, 41.110, 41.048, 40.845, 41.470

- Idle CPU (%): 0.001, 0.001, 0.001, 0.001, 0.001

- Idle wakeups (/s): 0.800, 0.600, 0.600, 0.600, 0.900

- Working-tree refresh (ms): 33.283, 39.558, 30.585, 32.427, 28.012, 27.543, 27.631, 28.550, 28.315, 27.882, 28.112, 28.363, 27.770, 27.679, 27.026, 27.475, 27.385, 28.717, 27.844, 27.421, 28.404, 26.611, 28.561, 27.341, 27.767, 27.185, 28.382, 27.162, 27.057, 28.586

- Initial repository loading (ms): 108.365, 96.978, 95.118, 87.058, 82.441, 83.671, 88.979, 80.732, 82.966, 81.543, 85.140, 83.482, 85.208, 82.198, 83.005, 80.867, 84.436, 81.415, 79.475, 82.749, 81.180, 84.024, 82.430, 83.017, 81.575, 79.772, 81.868, 80.019, 83.045, 83.509

### Tidex

- Launch to initial frame (ms): 219.600, 220.101, 228.571, 209.561, 226.775, 219.367, 216.317, 216.409, 237.471, 216.414, 220.470, 216.679, 225.105, 223.937, 223.560, 223.582, 211.646, 223.566, 236.520, 219.065

- Startup peak physical footprint (MiB): 29.251, 28.017, 28.376, 28.782, 27.923, 28.642, 29.173, 28.313, 28.454, 28.142, 28.938, 28.829, 27.860, 29.095, 28.720, 27.985, 28.188, 29.501, 28.751, 29.142

- Settled physical footprint (MiB): 41.704, 41.798, 42.079, 41.673, 42.017

- Idle CPU (%): 0.001, 0.001, 0.001, 0.001, 0.001

- Idle wakeups (/s): 0.700, 0.800, 0.999, 0.800, 0.900

- Working-tree refresh (ms): 29.862, 46.183, 24.737, 20.395, 18.884, 21.093, 18.533, 18.852, 18.238, 21.139, 17.810, 19.420, 17.987, 20.495, 19.383, 18.718, 17.430, 17.732, 18.875, 18.258, 18.043, 18.975, 19.116, 18.928, 18.182, 18.885, 18.646, 18.020, 17.845, 17.950

- Initial repository loading (ms): 113.795, 118.500, 81.554, 84.119, 90.153, 78.557, 74.146, 72.186, 73.698, 74.139, 72.994, 75.256, 74.561, 80.006, 75.422, 72.667, 72.456, 72.789, 72.761, 74.140, 73.950, 73.127, 78.444, 72.737, 73.216, 75.113, 75.061, 75.058, 74.173, 72.643

