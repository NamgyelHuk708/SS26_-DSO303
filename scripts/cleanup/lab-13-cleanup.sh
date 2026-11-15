#!/usr/bin/env bash
# END-OF-COURSE CLEANUP for Lab 13. Deletes dependencies inside-out.  DO NOT RUN NOW.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"
# shellcheck disable=SC1091
source "$REPO_ROOT/configs/course.env"
# shellcheck disable=SC1091
source "$REPO_ROOT/configs/lab-13.env" 2>/dev/null || true
CENTRAL="${USMS_LOG_GROUP_CENTRAL:-/usms/central/application}"
FN_LOG="${USMS_LOG_GROUP_NOTIFIER:-/aws/lambda/usms-transcript-notifier}"

cat << 'WARN'
This will permanently delete: the composite alarm and its two children (and their history), the
usms-overview dashboard, both metric filters, /usms/central/application AND EVERY EVENT IN IT,
the usms-transcripts-sampling rule, and USMSObservabilityWrite (after detaching it from two roles).
Metric DATA in USMS/Application cannot be deleted - CloudWatch metrics expire, they are never removed.
WARN
printf 'Type exactly: DELETE USMS OBSERVABILITY\n> '
read -r CONFIRM
[ "$CONFIRM" = "DELETE USMS OBSERVABILITY" ] || { echo "aborted"; exit 1; }

echo "1/7 composite alarm first (it references the others)"
aws cloudwatch delete-alarms --alarm-names usms-transcript-pipeline-down 2>/dev/null && echo "    deleted" || echo "    absent"
echo "2/7 child alarms"
aws cloudwatch delete-alarms --alarm-names usms-transcript-lag-high usms-notify-silence 2>/dev/null && echo "    deleted" || echo "    absent"
echo "3/7 dashboard"
aws cloudwatch delete-dashboards --dashboard-names usms-overview 2>/dev/null && echo "    deleted" || echo "    absent"
echo "4/7 metric filters"
aws logs delete-metric-filter --log-group-name "$FN_LOG" --filter-name usms-notify-count 2>/dev/null || true
aws logs delete-metric-filter --log-group-name "$CENTRAL" --filter-name usms-central-errors 2>/dev/null || true
echo "5/7 central log group and its events"
aws logs delete-log-group --log-group-name "$CENTRAL" 2>/dev/null && echo "    deleted" || echo "    absent"
echo "6/7 X-Ray sampling rule"
aws xray delete-sampling-rule --rule-name usms-transcripts-sampling 2>/dev/null && echo "    deleted" || echo "    absent or unsupported"
echo "7/7 USMSObservabilityWrite"
OBS_ARN=$(aws iam list-policies --scope Local --query "Policies[?PolicyName=='USMSObservabilityWrite'].Arn | [0]" --output text 2>/dev/null)
if [ -n "$OBS_ARN" ] && [ "$OBS_ARN" != "None" ]; then
  for role in usms-lambda-exec-role usms-ec2-app-role; do
    aws iam detach-role-policy --role-name "$role" --policy-arn "$OBS_ARN" 2>/dev/null && echo "    detached from $role" || true
  done
  aws iam delete-policy --policy-arn "$OBS_ARN" 2>/dev/null && echo "    deleted" || echo "    could not delete"
fi
echo "NOT deleted: the notifier's versions and alias (Lab 10), its log group, metric data."
