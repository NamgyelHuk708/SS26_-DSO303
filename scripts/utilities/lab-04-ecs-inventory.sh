#!/usr/bin/env bash
# Prints one line per ECS service in the USMS cluster with computed verdicts:
#   roles    = SAME if executionRoleArn == taskRoleArn, SEPARATE if they differ
#   publicip = RISK if assignPublicIp is ENABLED, OK if DISABLED, N/A if no networkConfiguration
# Also writes the same data as JSON to outputs/lab-04-ecs-inventory.json.
set -uo pipefail
# -e is NOT set on purpose: some services have no networkConfiguration (EC2 launch type)
# or a task definition with no role, and those lookups return None or fail.
# One odd service should be reported as N/A, not stop the whole inventory.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"
source "$REPO_ROOT/configs/course.env" 2>/dev/null || true
source "$REPO_ROOT/configs/lab-04.env" 2>/dev/null || true

CLUSTER="${USMS_ECS_CLUSTER:-usms-ecs-cluster}"
OUT_JSON="$REPO_ROOT/outputs/lab-04-ecs-inventory.json"
TMP=$(mktemp)

SERVICES=$(aws ecs list-services --cluster "$CLUSTER" --query 'serviceArns[]' --output text 2>/dev/null)

if [ -z "$SERVICES" ] || [ "$SERVICES" = "None" ]; then
  echo "No services found in $CLUSTER"
  echo "[]" > "$OUT_JSON"
  exit 0
fi

for arn in $SERVICES; do
  read -r NAME DESIRED RUNNING TASKDEF PUBIP <<< "$(aws ecs describe-services \
    --cluster "$CLUSTER" --services "$arn" \
    --query 'services[0].[serviceName,desiredCount,runningCount,taskDefinition,networkConfiguration.awsvpcConfiguration.assignPublicIp]' \
    --output text 2>/dev/null)"

  TD_SHORT="${TASKDEF##*/}"     # usms-enrolment:2

  EXEC=$(aws ecs describe-task-definition --task-definition "$TASKDEF" \
    --query 'taskDefinition.executionRoleArn' --output text 2>/dev/null || echo None)
  TASK=$(aws ecs describe-task-definition --task-definition "$TASKDEF" \
    --query 'taskDefinition.taskRoleArn' --output text 2>/dev/null || echo None)

  if [ "$EXEC" = "None" ] || [ "$TASK" = "None" ] || [ -z "$EXEC" ] || [ -z "$TASK" ]; then
    ROLES="N/A"
  elif [ "$EXEC" = "$TASK" ]; then
    ROLES="SAME"
  else
    ROLES="SEPARATE"
  fi

  case "${PUBIP:-None}" in
    ENABLED)  PUBLIC="RISK" ;;
    DISABLED) PUBLIC="OK" ;;
    *)        PUBLIC="N/A" ;;
  esac

  printf '%-20s desired=%-2s running=%-2s taskdef=%-18s roles=%-9s publicip=%s\n' \
    "$NAME" "$DESIRED" "$RUNNING" "$TD_SHORT" "$ROLES" "$PUBLIC"

  jq -n --arg name "$NAME" --arg desired "$DESIRED" --arg running "$RUNNING" \
        --arg taskdef "$TD_SHORT" --arg roles "$ROLES" --arg publicip "$PUBLIC" \
        '{service:$name, desired:($desired|tonumber? // $desired), running:($running|tonumber? // $running), taskdef:$taskdef, roles:$roles, publicip:$publicip}' >> "$TMP"
done

jq -s '.' "$TMP" > "$OUT_JSON"
rm -f "$TMP"
