# Kvist release performance report

Generated: 2026-07-19T04:33:01.468Z  
Commit: `e2f9bdb952b4a24c29e4f168763fb2e0e7b84ca0` (dirty)  
System: Version 27.0 (Build 26A5378j), 12 logical CPUs  
Build: release

Raw machine-readable samples are in [`raw-results.json`](raw-results.json).

## Guardrails

| Status | Repository | Metric | Statistic | Measured | Limit |
| --- | --- | --- | --- | ---: | ---: |
| PASS | All | App bundle | value | 6.110 MiB | ≤ 6.250 MiB |
| PASS | All | Compressed app | value | 1.428 MiB | ≤ 1.500 MiB |
| PASS | GitLite | Launch | median | 219.816 ms | ≤ 300.000 ms |
| PASS | GitLite | Launch | p95 | 229.208 ms | ≤ 400.000 ms |
| PASS | GitLite | Startup peak footprint | maximum | 30.345 MiB | ≤ 180.000 MiB |
| PASS | GitLite | Settled footprint | maximum | 45.985 MiB | ≤ 50.000 MiB |
| PASS | GitLite | Idle CPU | maximum | 0.001 % | ≤ 0.010 % |
| PASS | GitLite | Idle wakeups | maximum | 0.800 /s | ≤ 1.200 /s |
| PASS | GitLite | Working-tree refresh | median | 9.679 ms | ≤ 10.549 ms |
| PASS | GitLite | Working-tree refresh | p95 | 11.738 ms | ≤ 13.921 ms |
| PASS | GitLite | Initial Git loading | median | 64.341 ms | ≤ 90.000 ms |
| PASS | GitLite | Initial Git loading | p95 | 80.276 ms | ≤ 150.000 ms |
| PASS | GitLite | External edit to publication | median | 143.217 ms | ≤ 250.000 ms |
| PASS | GitLite | External edit to publication | p95 | 155.042 ms | ≤ 350.000 ms |
| PASS | GitLite | Event storm settle | p95 | 149.534 ms | ≤ 450.000 ms |
| PASS | GitLite | Event storm writes | maximum | 10.264 ms | ≤ 100.000 ms |
| PASS | GitLite | External edit working-tree snapshots | maximum | 1.000 count | ≤ 1.000 count |
| PASS | GitLite | External edit full snapshots | maximum | 0.000 count | ≤ 0.000 count |
| PASS | GitLite | Event storm working-tree snapshots | maximum | 1.000 count | ≤ 1.000 count |
| PASS | GitLite | Event storm full snapshots | maximum | 0.000 count | ≤ 0.000 count |
| PASS | Paeonia | Launch | median | 216.362 ms | ≤ 300.000 ms |
| PASS | Paeonia | Launch | p95 | 232.934 ms | ≤ 400.000 ms |
| PASS | Paeonia | Startup peak footprint | maximum | 30.438 MiB | ≤ 180.000 MiB |
| PASS | Paeonia | Settled footprint | maximum | 41.470 MiB | ≤ 50.000 MiB |
| PASS | Paeonia | Idle CPU | maximum | 0.001 % | ≤ 0.010 % |
| PASS | Paeonia | Idle wakeups | maximum | 0.800 /s | ≤ 1.200 /s |
| PASS | Paeonia | Working-tree refresh | median | 27.706 ms | ≤ 30.649 ms |
| PASS | Paeonia | Working-tree refresh | p95 | 36.033 ms | ≤ 36.612 ms |
| PASS | Paeonia | Initial Git loading | median | 82.902 ms | ≤ 90.000 ms |
| PASS | Paeonia | Initial Git loading | p95 | 91.885 ms | ≤ 150.000 ms |
| PASS | Paeonia | External edit to publication | median | 146.579 ms | ≤ 250.000 ms |
| PASS | Paeonia | External edit to publication | p95 | 152.268 ms | ≤ 350.000 ms |
| PASS | Paeonia | Event storm settle | p95 | 160.576 ms | ≤ 450.000 ms |
| PASS | Paeonia | Event storm writes | maximum | 14.351 ms | ≤ 100.000 ms |
| PASS | Paeonia | External edit working-tree snapshots | maximum | 1.000 count | ≤ 1.000 count |
| PASS | Paeonia | External edit full snapshots | maximum | 0.000 count | ≤ 0.000 count |
| PASS | Paeonia | Event storm working-tree snapshots | maximum | 1.000 count | ≤ 1.000 count |
| PASS | Paeonia | Event storm full snapshots | maximum | 0.000 count | ≤ 0.000 count |
| PASS | Tidex | Launch | median | 220.209 ms | ≤ 300.000 ms |
| PASS | Tidex | Launch | p95 | 241.059 ms | ≤ 400.000 ms |
| PASS | Tidex | Startup peak footprint | maximum | 31.032 MiB | ≤ 180.000 MiB |
| PASS | Tidex | Settled footprint | maximum | 41.970 MiB | ≤ 50.000 MiB |
| PASS | Tidex | Idle CPU | maximum | 0.001 % | ≤ 0.010 % |
| PASS | Tidex | Idle wakeups | maximum | 0.800 /s | ≤ 1.200 /s |
| PASS | Tidex | Working-tree refresh | median | 18.324 ms | ≤ 20.750 ms |
| PASS | Tidex | Working-tree refresh | p95 | 22.213 ms | ≤ 32.849 ms |
| PASS | Tidex | Initial Git loading | median | 73.029 ms | ≤ 90.000 ms |
| PASS | Tidex | Initial Git loading | p95 | 83.164 ms | ≤ 150.000 ms |
| PASS | Tidex | External edit to publication | median | 150.967 ms | ≤ 250.000 ms |
| PASS | Tidex | External edit to publication | p95 | 159.571 ms | ≤ 350.000 ms |
| PASS | Tidex | Event storm settle | p95 | 171.119 ms | ≤ 450.000 ms |
| PASS | Tidex | Event storm writes | maximum | 12.321 ms | ≤ 100.000 ms |
| PASS | Tidex | External edit working-tree snapshots | maximum | 1.000 count | ≤ 1.000 count |
| PASS | Tidex | External edit full snapshots | maximum | 0.000 count | ≤ 0.000 count |
| PASS | Tidex | Event storm working-tree snapshots | maximum | 1.000 count | ≤ 1.000 count |
| PASS | Tidex | Event storm full snapshots | maximum | 0.000 count | ≤ 0.000 count |

## Summary

| Repository | Metric | Samples | Median | p95 |
| --- | --- | ---: | ---: | ---: |
| All | App bundle | 1 | 6.110 MiB | 6.110 MiB |
| All | Compressed app | 1 | 1.428 MiB | 1.428 MiB |
| GitLite | Launch to initial frame | 20 | 219.816 ms | 229.208 ms |
| GitLite | Startup peak physical footprint | 20 | 28.938 MiB | 30.298 MiB |
| GitLite | Settled physical footprint | 5 | 45.626 MiB | 45.985 MiB |
| GitLite | Idle CPU | 5 | 0.001 % | 0.001 % |
| GitLite | Idle wakeups | 5 | 0.700 /s | 0.800 /s |
| GitLite | Working-tree refresh | 30 | 9.679 ms | 11.738 ms |
| GitLite | Initial repository loading | 30 | 64.341 ms | 80.276 ms |
| GitLite | External edit to publication | 30 | 143.217 ms | 155.042 ms |
| GitLite | Event storm settle | 10 | 136.290 ms | 149.534 ms |
| GitLite | Event storm writes | 10 | 9.843 ms | 10.264 ms |
| Paeonia | Launch to initial frame | 20 | 216.362 ms | 232.934 ms |
| Paeonia | Startup peak physical footprint | 20 | 28.642 MiB | 30.407 MiB |
| Paeonia | Settled physical footprint | 5 | 41.251 MiB | 41.470 MiB |
| Paeonia | Idle CPU | 5 | 0.001 % | 0.001 % |
| Paeonia | Idle wakeups | 5 | 0.700 /s | 0.800 /s |
| Paeonia | Working-tree refresh | 30 | 27.706 ms | 36.033 ms |
| Paeonia | Initial repository loading | 30 | 82.902 ms | 91.885 ms |
| Paeonia | External edit to publication | 30 | 146.579 ms | 152.268 ms |
| Paeonia | Event storm settle | 10 | 141.226 ms | 160.576 ms |
| Paeonia | Event storm writes | 10 | 9.577 ms | 14.351 ms |
| Tidex | Launch to initial frame | 20 | 220.209 ms | 241.059 ms |
| Tidex | Startup peak physical footprint | 20 | 28.977 MiB | 30.735 MiB |
| Tidex | Settled physical footprint | 5 | 41.548 MiB | 41.970 MiB |
| Tidex | Idle CPU | 5 | 0.000 % | 0.001 % |
| Tidex | Idle wakeups | 5 | 0.600 /s | 0.800 /s |
| Tidex | Working-tree refresh | 30 | 18.324 ms | 22.213 ms |
| Tidex | Initial repository loading | 30 | 73.029 ms | 83.164 ms |
| Tidex | External edit to publication | 30 | 150.967 ms | 159.571 ms |
| Tidex | Event storm settle | 10 | 150.052 ms | 171.119 ms |
| Tidex | Event storm writes | 10 | 10.896 ms | 12.321 ms |

## Raw samples

### GitLite

- Launch to initial frame (ms): 203.849, 212.126, 218.413, 219.755, 220.102, 220.355, 229.208, 236.887, 223.723, 220.280, 216.193, 214.760, 211.766, 211.843, 219.876, 224.667, 214.432, 224.437, 220.085, 216.234

- Startup peak physical footprint (MiB): 27.938, 30.298, 28.345, 27.970, 28.095, 29.079, 29.579, 28.376, 28.048, 30.345, 28.204, 28.079, 29.517, 28.032, 29.485, 29.860, 29.329, 29.235, 28.798, 30.095

- Settled physical footprint (MiB): 45.595, 45.532, 45.876, 45.626, 45.985

- Idle CPU (%): 0.000, 0.001, 0.001, 0.000, 0.001

- Idle wakeups (/s): 0.600, 0.700, 0.800, 0.600, 0.700

- Working-tree refresh (ms): 11.247, 13.662, 11.689, 10.741, 11.738, 10.542, 10.593, 9.723, 9.763, 10.043, 9.706, 9.461, 9.322, 9.274, 9.209, 9.489, 9.077, 8.869, 9.114, 8.790, 9.870, 9.678, 9.192, 9.078, 9.949, 9.535, 9.681, 9.829, 9.362, 9.587

- Initial repository loading (ms): 80.276, 97.057, 75.841, 77.951, 72.771, 73.222, 65.918, 64.553, 65.299, 64.344, 64.339, 64.028, 64.457, 64.386, 68.584, 64.748, 62.725, 64.167, 62.749, 61.138, 64.212, 61.209, 63.978, 62.170, 63.875, 60.759, 63.060, 63.878, 67.233, 63.483

- External edit to publication (ms): 171.256, 110.331, 135.761, 120.769, 120.289, 103.803, 149.490, 144.083, 147.827, 139.003, 142.311, 151.070, 146.727, 144.840, 143.891, 142.615, 146.050, 139.671, 150.059, 155.042, 138.347, 151.269, 123.484, 150.280, 135.287, 154.486, 143.819, 140.826, 106.664, 139.773

- Event storm settle (ms): 144.513, 146.000, 117.678, 129.335, 134.974, 137.606, 138.205, 128.475, 109.226, 149.534

- Event storm writes (ms): 10.019, 9.489, 10.190, 9.825, 9.935, 10.264, 9.861, 8.415, 9.676, 9.359

- External edit working-tree snapshots (count): 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000

- External edit full snapshots (count): 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000

- Event storm working-tree snapshots (count): 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000

- Event storm full snapshots (count): 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000

### Paeonia

- Launch to initial frame (ms): 201.350, 232.934, 216.342, 220.456, 228.221, 198.476, 211.390, 212.498, 209.523, 213.402, 224.567, 243.941, 216.098, 219.774, 211.300, 198.364, 216.382, 222.881, 224.268, 227.284

- Startup peak physical footprint (MiB): 29.923, 28.563, 28.438, 28.657, 28.470, 30.126, 29.032, 28.626, 29.626, 28.579, 28.204, 30.438, 28.595, 28.345, 28.360, 28.188, 30.407, 29.767, 29.329, 30.095

- Settled physical footprint (MiB): 41.470, 41.251, 41.157, 41.376, 41.095

- Idle CPU (%): 0.001, 0.001, 0.000, 0.000, 0.001

- Idle wakeups (/s): 0.600, 0.700, 0.500, 0.800, 0.700

- Working-tree refresh (ms): 38.940, 36.033, 35.838, 29.483, 27.242, 28.890, 27.106, 27.612, 27.092, 28.504, 27.811, 27.717, 27.300, 28.378, 28.119, 27.505, 28.275, 27.055, 27.772, 27.059, 27.243, 26.914, 27.703, 27.609, 27.231, 27.709, 26.613, 28.099, 27.675, 28.820

- Initial repository loading (ms): 107.425, 91.885, 88.021, 80.714, 82.911, 80.229, 81.113, 83.650, 83.050, 84.410, 80.507, 80.029, 80.686, 89.607, 82.894, 84.164, 82.310, 80.863, 82.708, 81.062, 82.469, 80.470, 81.545, 83.977, 81.408, 84.467, 84.268, 86.909, 83.711, 83.486

- External edit to publication (ms): 177.743, 126.157, 149.881, 148.965, 139.880, 118.567, 151.776, 144.229, 151.131, 150.882, 152.268, 143.345, 141.544, 141.366, 143.522, 151.675, 148.978, 150.393, 142.071, 142.651, 140.618, 123.189, 143.414, 146.501, 148.021, 150.762, 146.656, 150.920, 119.808, 146.915

- Event storm settle (ms): 133.602, 139.184, 160.576, 141.682, 142.901, 133.102, 141.747, 134.271, 140.771, 142.695

- Event storm writes (ms): 8.314, 8.260, 14.351, 9.582, 9.839, 9.365, 10.098, 9.748, 9.572, 9.093

- External edit working-tree snapshots (count): 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000

- External edit full snapshots (count): 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000

- Event storm working-tree snapshots (count): 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000

- Event storm full snapshots (count): 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000

### Tidex

- Launch to initial frame (ms): 232.669, 236.862, 225.214, 211.458, 233.225, 215.141, 216.681, 220.269, 220.282, 224.470, 249.498, 217.849, 215.857, 218.163, 218.576, 206.488, 207.848, 220.149, 223.853, 241.059

- Startup peak physical footprint (MiB): 30.423, 28.485, 27.860, 28.673, 29.032, 29.063, 28.548, 27.907, 28.235, 27.985, 30.735, 28.923, 28.392, 29.267, 30.001, 30.595, 31.032, 30.548, 29.063, 28.563

- Settled physical footprint (MiB): 41.970, 41.501, 41.548, 41.485, 41.751

- Idle CPU (%): 0.000, 0.000, 0.001, 0.001, 0.000

- Idle wakeups (/s): 0.600, 0.600, 0.700, 0.800, 0.599

- Working-tree refresh (ms): 26.286, 22.213, 19.229, 21.691, 18.815, 17.916, 17.765, 17.841, 18.441, 18.537, 18.317, 17.753, 17.176, 17.874, 17.555, 18.289, 18.381, 17.349, 18.234, 18.193, 19.186, 17.544, 17.921, 18.373, 18.349, 18.330, 18.244, 18.595, 19.730, 18.914

- Initial repository loading (ms): 96.486, 83.164, 80.558, 78.267, 72.577, 72.319, 70.672, 73.556, 70.837, 74.501, 71.290, 71.459, 72.135, 69.816, 72.688, 74.031, 72.226, 75.087, 75.840, 74.854, 76.046, 71.452, 72.846, 74.364, 74.174, 72.693, 74.050, 72.984, 70.662, 73.075

- External edit to publication (ms): 139.914, 143.101, 148.868, 142.264, 163.665, 135.935, 136.427, 147.010, 158.681, 148.182, 144.836, 148.989, 143.440, 155.089, 155.997, 145.702, 133.339, 155.446, 154.168, 159.571, 152.944, 136.223, 157.391, 158.535, 155.511, 156.130, 157.412, 155.640, 153.970, 134.146

- Event storm settle (ms): 151.152, 149.470, 149.674, 152.648, 145.970, 154.856, 150.430, 140.157, 147.049, 171.119

- Event storm writes (ms): 9.561, 10.480, 11.239, 9.554, 10.554, 10.169, 11.703, 11.483, 12.187, 12.321

- External edit working-tree snapshots (count): 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000

- External edit full snapshots (count): 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000

- Event storm working-tree snapshots (count): 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000, 1.000

- Event storm full snapshots (count): 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000, 0.000

