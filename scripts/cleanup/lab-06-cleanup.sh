#!/usr/bin/env bash
# END OF COURSE ONLY. Removes Lab 06, dependencies first.
# Order: scheduled actions -> scaling policies -> the custom alarm -> deregister the target.
# Run FIRST: lab-05-cleanup.sh and lab-04-cleanup.sh both REFUSE
# while a scalable target still exists for this service.
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"
source "$REPO_ROOT/configs/course.env"
source "$REPO_ROOT/configs/lab-04.env"
source "$REPO_ROOT/configs/lab-06.env"

cat <<'WARN'
============================================================
  This deletes the USMS enrolment service's SCALING only:
    - both scheduled actions
    - all three scaling policies, and with them the four
      CloudWatch alarms target tracking created for you
    - the custom alarm usms-enrolment-queue-high
    - the scalable target registration

  It does NOT touch the ECS service, the task definition,
  the cluster, the load balancer or the target group.

  Run FIRST, then lab-05-cleanup.sh, then lab-04-cleanup.sh.
============================================================
WARN

read -r -p 'Type exactly: DELETE USMS SCALING  > ' answer
[ "$answer" = "DELETE USMS SCALING" ] || { echo "aborted"; exit 1; }

say() { printf '\n-- %s\n' "$1"; }

NS="$USMS_SCALABLE_NAMESPACE"
RID="$USMS_SCALABLE_RESOURCE_ID"
DIM="$USMS_SCALABLE_DIMENSION"

say "scheduled actions first"
for a in "$USMS_SCHEDULED_OUT" "$USMS_SCHEDULED_IN"; do
  aws application-autoscaling delete-scheduled-action \
    --service-namespace "$NS" --resource-id "$RID" --scalable-dimension "$DIM" \
    --scheduled-action-name "$a" >/dev/null 2>&1 \
    && echo "   deleted $a" || echo "   $a already gone"
done

say "any OTHER scheduled action left behind by an exercise"
for a in $(aws application-autoscaling describe-scheduled-actions \
             --service-namespace "$NS" --resource-id "$RID" \
             --query 'ScheduledActions[].ScheduledActionName' --output text 2>/dev/null || true); do
  aws application-autoscaling delete-scheduled-action \
    --service-namespace "$NS" --resource-id "$RID" --scalable-dimension "$DIM" \
    --scheduled-action-name "$a" >/dev/null 2>&1 && echo "   deleted $a" || true
done

say "scaling policies: deleting a target tracking policy also deletes ITS managed alarms"
for p in $(aws application-autoscaling describe-scaling-policies \
             --service-namespace "$NS" --resource-id "$RID" \
             --query 'ScalingPolicies[].PolicyName' --output text 2>/dev/null || true); do
  aws application-autoscaling delete-scaling-policy \
    --service-namespace "$NS" --resource-id "$RID" --scalable-dimension "$DIM" \
    --policy-name "$p" >/dev/null 2>&1 \
    && echo "   deleted $p" || echo "   $p already gone"
done

say "the alarm YOU wrote: nothing deletes this for you"
aws cloudwatch delete-alarms --alarm-names "$USMS_ALARM_QUEUE_HIGH" >/dev/null 2>&1 \
  && echo "   deleted $USMS_ALARM_QUEUE_HIGH" || echo "   already gone"

say "any managed alarm the policy deletions did not take with them"
LEFT=$(aws cloudwatch describe-alarms --alarm-name-prefix "TargetTracking-$RID" \
         --query 'MetricAlarms[].AlarmName' --output text 2>/dev/null || true)
if [ -n "$LEFT" ] && [ "$LEFT" != "None" ]; then
  # shellcheck disable=SC2086
  aws cloudwatch delete-alarms --alarm-names $LEFT >/dev/null 2>&1 \
    && echo "   deleted orphaned managed alarms" || true
else
  echo "   none left"
fi

say "deregister the scalable target LAST"
aws application-autoscaling deregister-scalable-target \
  --service-namespace "$NS" --resource-id "$RID" --scalable-dimension "$DIM" >/dev/null 2>&1 \
  && echo "   deregistered $RID" || echo "   already deregistered"

say "what is deliberately NOT deleted"
cat <<'KEPT'
   AWSServiceRoleForApplicationAutoScaling_ECSService - account-wide; delete-service-linked-role is the owner's call.
   The USMS/Enrolment custom metric - CloudWatch has no delete-metric; it expires on its own.
   usms-enrolment-svc, task definition, cluster, load balancer - owned by lab-05 and lab-04 cleanup.
KEPT

echo
echo "Lab 06 teardown complete. scripts/cleanup/lab-05-cleanup.sh may now run."
