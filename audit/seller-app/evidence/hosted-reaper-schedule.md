# Hosted evidence — reaper schedule actually achieved on GitHub Actions

Source: GitHub Actions API, `list_workflow_runs` for `.github/workflows/reaper-cron.yml`, event=schedule,
repository psuvraneel-cyber/LiveDrop, queried 2026-10-03 during this audit (read-only). total_count=110 scheduled runs.
Configured schedule: `cron: '*/5 * * * *'` (every 5 minutes = 288 runs/day). All 30 runs below concluded `success`.

| run # | started (UTC) | gap to previous run |
|---|---|---|
| 111 | 2026-10-03 10:37 | 4h59m |
| 110 | 2026-10-03 05:38 | 5h12m |
| 109 | 2026-10-03 00:26 | 3h22m |
| 108 | 2026-10-02 21:03 | 4h17m |
| 107 | 2026-10-02 16:45 | 5h21m |
| 106 | 2026-10-02 11:23 | 5h36m |
| 105 | 2026-10-02 05:47 | 5h35m |
| 104 | 2026-10-02 00:12 | 3h37m |
| 103 | 2026-10-01 20:35 | 4h50m |
| 102 | 2026-10-01 15:44 | 6h56m |
| 101 | 2026-10-01 08:47 | 6h46m |
| 100 | 2026-10-01 02:01 | 3h03m |
| 99 | 2026-09-30 22:58 | 3h54m |
| 98 | 2026-09-30 19:03 | 5h07m |
| 97 | 2026-09-30 13:56 | 6h38m |
| 96 | 2026-09-30 07:17 | 5h49m |
| 95 | 2026-09-30 01:28 | 3h01m |
| 94 | 2026-09-29 22:26 | 4h07m |
| 93 | 2026-09-29 18:19 | 5h34m |
| 92 | 2026-09-29 12:45 | 6h41m |
| 91 | 2026-09-29 06:04 | 5h37m |
| 90 | 2026-09-29 00:26 | 4h08m |
| 89 | 2026-09-28 20:17 | 6h28m |
| 88 | 2026-09-28 13:49 | 7h42m |
| 87 | 2026-09-28 06:06 | 5h16m |
| 86 | 2026-09-28 00:50 | 2h38m |
| 85 | 2026-09-27 22:11 | 3h02m |
| 84 | 2026-09-27 19:09 | 3h45m |
| 83 | 2026-09-27 15:23 | 4h35m |
| 82 | 2026-09-27 10:48 | (oldest in sample) |

Sample: 30 runs over 143.8 h → 5.0 runs/day (configured: 288/day).
Gap min 2h38m, median 5h07m, max 7h42m.

Consequence: `release_expired_holds()` is the only code path that turns an expired 15-minute hold back into an
available piece (create_order_with_reservation in 022 does not lazily expire holds). In production the effective
hold is therefore 15 minutes + up to ~8 hours. See SA-OPS-001.
