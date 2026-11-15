# Lab 13 notes

## Cross-lab checks after Lab 13
- verify-lab-10: PASS=51 FAIL=0 with live -> 4 (moved forward from Lab 10's version 1).
- verify-lab-06: PASS=24 FAIL=18 (its report recorded 23/19 on Path C - Application Auto Scaling does not exist on
  this build). All 18 failures are the scaling-API checks; one more check passes than at submission. Lab 13 changed
  nothing Lab 6 owns, and the USMS_APP_METRIC_NAMESPACE rename keeps lab-06.env's USMS_METRIC_NAMESPACE intact.
