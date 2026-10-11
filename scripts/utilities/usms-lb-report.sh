#!/usr/bin/env bash
# Prints the full routing decision table for every usms-* Application Load Balancer.
# Also writes outputs/lab-05-lb-report.json.
set -uo pipefail
# -e is NOT set on purpose: a load balancer with no listeners, a listener with no
# rules or an empty target group makes some calls return nothing or fail. One odd
# object should be printed as "none", not stop the whole report.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"
source "$REPO_ROOT/configs/course.env" 2>/dev/null || true
OUT_JSON="$REPO_ROOT/outputs/lab-05-lb-report.json"

LBS=$(aws elbv2 describe-load-balancers --output json 2>/dev/null \
      | jq -c '[.LoadBalancers[]? | select(.LoadBalancerName | startswith("usms-"))]')
[ -z "$LBS" ] && LBS='[]'

# Build one big JSON document, then print it. Python does the sorting/formatting,
# the shell only makes the AWS calls.
REPORT='[]'
for lb in $(echo "$LBS" | jq -r '.[].LoadBalancerArn'); do
  LB=$(echo "$LBS" | jq -c --arg a "$lb" '.[] | select(.LoadBalancerArn==$a)')
  LISTENERS=$(aws elbv2 describe-listeners --load-balancer-arn "$lb" --output json 2>/dev/null \
              | jq -c '.Listeners // []')
  [ -z "$LISTENERS" ] && LISTENERS='[]'
  LJSON='[]'
  for l in $(echo "$LISTENERS" | jq -r '.[].ListenerArn'); do
    L=$(echo "$LISTENERS" | jq -c --arg a "$l" '.[] | select(.ListenerArn==$a)')
    RULES=$(aws elbv2 describe-rules --listener-arn "$l" --output json 2>/dev/null | jq -c '.Rules // []')
    [ -z "$RULES" ] && RULES='[]'
    # add target counts to every forward action
    RJSON='[]'
    for i in $(seq 0 $(( $(echo "$RULES" | jq 'length') - 1 ))); do
      R=$(echo "$RULES" | jq -c ".[$i]")
      TG=$(echo "$R" | jq -r '.Actions[0].TargetGroupArn // empty')
      if [ -n "$TG" ]; then
        TH=$(aws elbv2 describe-target-health --target-group-arn "$TG" --output json 2>/dev/null \
             | jq -c '.TargetHealthDescriptions // []')
        [ -z "$TH" ] && TH='[]'
        R=$(echo "$R" | jq -c --argjson th "$TH" \
            '. + {targets: ($th|length), healthy: ([$th[] | select(.TargetHealth.State=="healthy")] | length)}')
      fi
      RJSON=$(echo "$RJSON" | jq -c --argjson r "$R" '. + [$r]')
    done
    LJSON=$(echo "$LJSON" | jq -c --argjson l "$L" --argjson r "$RJSON" '. + [$l + {rules: $r}]')
  done
  REPORT=$(echo "$REPORT" | jq -c --argjson lb "$LB" --argjson l "$LJSON" '. + [$lb + {listeners: $l}]')
done

echo "$REPORT" | jq '.' > "$OUT_JSON"

python3 - "$OUT_JSON" << 'PY'
import json, sys
data = json.load(open(sys.argv[1]))
if not data:
    print("no usms-* load balancers found")
def prio(r):
    # Priority is a string; the default action's priority is the word "default".
    # Map "default" to a huge number so it always sorts LAST (evaluation order).
    p = r.get("Priority", "default")
    return 10**9 if p == "default" else int(p)
for lb in data:
    print(f'{lb["LoadBalancerName"]:<20} {lb.get("Scheme","?"):<16} {lb.get("Type","?"):<12} '
          f'{(lb.get("State") or {}).get("Code","?"):<8} AZs={len(lb.get("AvailabilityZones") or [])}  '
          f'SGs={len(lb.get("SecurityGroups") or [])}')
    if not lb["listeners"]:
        print("  (no listeners)")
    for l in lb["listeners"]:
        print(f'  {l.get("Protocol","?")}:{l.get("Port","?")}')
        rules = sorted(l["rules"], key=prio)
        if not rules:
            print("    (no rules returned)")
        for r in rules:
            conds = r.get("Conditions") or []
            if conds:
                c = conds[0]
                vals = (c.get("PathPatternConfig") or {}).get("Values") or c.get("Values") or []
                cond = f'{c.get("Field","?"):<13} {",".join(vals):<28}'
            else:
                cond = f'{"-":<13} {"":<28}'
            a = (r.get("Actions") or [{}])[0]
            t = a.get("Type", "?")
            if t == "forward":
                tg = (a.get("TargetGroupArn") or "").split("/")[1] if a.get("TargetGroupArn") else "?"
                act = f'-> {tg}  ({r.get("targets",0)} targets, {r.get("healthy",0)} healthy)'
            elif t == "fixed-response":
                act = f'-> fixed-response {(a.get("FixedResponseConfig") or {}).get("StatusCode","?")}'
            elif t == "redirect":
                rc = a.get("RedirectConfig") or {}
                act = f'-> redirect {rc.get("StatusCode","?")} to {rc.get("Protocol","#{protocol}")}:{rc.get("Port","#{port}")}'
            else:
                act = f'-> {t}'
            print(f'    prio  {str(r.get("Priority")):<8} {cond} {act}')
PY
