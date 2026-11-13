# Lab 10 - files prepared in advance (unzipped into the repo)

| File | Step | Notes |
|---|---|---|
| labs/lab-10-lambda-edge/edge-viewer-request/index.mjs | 7 | exactly as the lab; tested with Node (allow + deny) |
| labs/lab-10-lambda-edge/edge-origin-response/index.mjs | 12 | exactly as the lab; tested with Node |
| labs/lab-10-lambda-edge/transcript-notifier/notifier.py | 17 | exactly as the lab; py_compile OK |
| policies/trust-lambda-edge.json | 6 | **changed**: two statements - lambda.amazonaws.com KEEPS the Lab 09 Exercise 2 confused-deputy conditions; edgelambda.amazonaws.com in its own statement. The lab's single unconditioned statement would have undone Lab 09 |
| templates/lab-10-viewer-request-event.json | 9 | requestId lab10-allow-0001 |
| templates/lab-10-origin-response-event.json | 13 | |
| templates/lab-10-bucket-notification.json | 20 | alias ARN filled in (account and name are fixed) |
| templates/lab-10-s3-event.json | 21 | bucket name filled in |
| scripts/utilities/usms-edge-simulate.sh | 16 | as the lab; tested end to end with the real handlers |
| scripts/utilities/verify-lab-10.sh | 8.1 | 51 checks; two fixes: role ARN -> name, and the .gitkeep check |
| scripts/cleanup/lab-10-cleanup.sh | 8.2 | NOT RUN |

Written live: templates/lab-10-viewer-request-denied.json (Step 9 Your turn), templates/lab-10-distribution-config.json
(Step 15 - needs a timestamp and the published version ARNs), configs/lab-10.env (Step 23), outputs/*.
