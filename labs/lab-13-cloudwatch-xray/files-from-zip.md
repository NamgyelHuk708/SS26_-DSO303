# Lab 13 - files prepared in advance

| File | Step | Notes |
|---|---|---|
| labs/lab-13-cloudwatch-xray/transcript-notifier-v2/notifier.py | 13 | the lab's handler, unchanged; tested locally against templates/lab-10-s3-event.json (telemetry failure never fails the invocation; Faculty from that key = "evidence") |
| policies/usms-observability-write-policy.json | 12 | as the lab |
| templates/lab-13-sampling-rule.json, lab-13-dashboard.json | 18, 22 | as the lab (5 widgets, no overlap - checked) |
| scripts/utilities/usms-emit-telemetry.sh | 17 | as the lab |
| scripts/utilities/verify-lab-13.sh | 8.1 | 49 checks; MY FIXES: role ARNs -> names (lab-01.env stores ARNs); describe-metric-filters --filter-name-prefix needs --log-group-name; .gitkeep |
| scripts/cleanup/lab-13-cleanup.sh | 8.2 | NOT RUN |

Written live: templates/lab-13-metric-data.json (11), lab-13-segment-*.json (15, 16), configs/lab-13.env (25).
Tags: the lab page says Lab=08; I use Lab=13.
