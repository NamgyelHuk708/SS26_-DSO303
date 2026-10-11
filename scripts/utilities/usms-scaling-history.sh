#!/usr/bin/env bash
# Exports the scaling configuration and history for usms-enrolment-svc as one JSON file.
# Every identifier is discovered. Tolerates Application Auto Scaling being unimplemented.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"
source "$REPO_ROOT/configs/course.env" 2>/dev/null || true
OUT="$REPO_ROOT/outputs/lab-06-scaling-history.json"

SVC_ARN=$(aws ecs describe-services --cluster usms-ecs-cluster --services usms-enrolment-svc \
  --query 'services[0].serviceArn' --output text)
RID="${SVC_ARN##*:}"

grab() { "$@" --output json 2>/dev/null || echo '{"error":"not available on this endpoint"}'; }

TARGETS=$(grab aws application-autoscaling describe-scalable-targets --service-namespace ecs --resource-ids "$RID")
POLICIES=$(grab aws application-autoscaling describe-scaling-policies --service-namespace ecs --resource-id "$RID")
SCHED=$(grab aws application-autoscaling describe-scheduled-actions --service-namespace ecs --resource-id "$RID")
ACTS=$(grab aws application-autoscaling describe-scaling-activities --service-namespace ecs --resource-id "$RID" --include-not-scaled-activities)
ALARMS=$(grab aws cloudwatch describe-alarms --alarm-name-prefix usms-enrolment-)
SERVICE=$(grab aws ecs describe-services --cluster usms-ecs-cluster --services usms-enrolment-svc)

python3 - "$OUT" "$RID" << PY
import json, sys, datetime
def j(s):
    try: return json.loads(s)
    except Exception: return {"error": "unparseable"}
doc = {
  "generated": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
  "resourceId": sys.argv[2],
  "scalableTargets": j('''$TARGETS'''),
  "scalingPolicies": j('''$POLICIES'''),
  "scheduledActions": j('''$SCHED'''),
  "scalingActivities": j('''$ACTS'''),
  "alarms": j('''$ALARMS'''),
  "service": j('''$SERVICE'''),
}
json.dump(doc, open(sys.argv[1], "w"), indent=2, default=str)
PY
python3 -m json.tool "$OUT" > /dev/null && echo "valid JSON: $OUT ($(wc -c < "$OUT") bytes)"
