#!/usr/bin/env bash
# Prints the ResourceLabel for ALBRequestCountPerTarget:
#   app/<lb-name>/<lb-id>/targetgroup/<tg-name>/<tg-id>
# Usage: usms-resource-label.sh [lb-name] [tg-name]
# Derives both ARNs from the API. Does NOT read configs/lab-05.env for them.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/configs/course.env" 2>/dev/null || true

LB_NAME="${1:-usms-enrolment-alb}"
TG_NAME="${2:-usms-enrolment-tg}"

LB_ARN=$(aws elbv2 describe-load-balancers --names "$LB_NAME" \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null)
TG_ARN=$(aws elbv2 describe-target-groups --names "$TG_NAME" \
  --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null)

if [ -z "$LB_ARN" ] || [ "$LB_ARN" = "None" ] || [ -z "$TG_ARN" ] || [ "$TG_ARN" = "None" ]; then
  echo "error: could not find load balancer '$LB_NAME' or target group '$TG_NAME'" >&2
  exit 1
fi

# The two suffixes need different treatment:
#  - LB ARN:  ...:loadbalancer/app/NAME/ID  -> the label wants "app/NAME/ID",
#    so the word "loadbalancer/" must be CUT OFF (strip everything up to ":loadbalancer/").
#  - TG ARN:  ...:targetgroup/NAME/ID       -> the label wants "targetgroup/NAME/ID",
#    so the word "targetgroup/" must be KEPT (strip only up to the last ":").
LB_SUFFIX="${LB_ARN#*:loadbalancer/}"
TG_SUFFIX="${TG_ARN##*:}"

LABEL="${LB_SUFFIX}/${TG_SUFFIX}"

# Sanity checks before printing
IFS='/' read -r -a PARTS <<< "$LABEL"
if [ "${#PARTS[@]}" -ne 6 ] || [ "${PARTS[0]}" != "app" ] || [ "${PARTS[3]}" != "targetgroup" ] \
   || [ "${PARTS[1]}" != "$LB_NAME" ] || [ "${PARTS[4]}" != "$TG_NAME" ]; then
  echo "error: label does not look right: $LABEL" >&2
  exit 1
fi

echo "$LABEL"
