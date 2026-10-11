#!/usr/bin/env bash
# Prints the scaling decision table for every usms-* ECS scalable target.
# Handles a build where Application Auto Scaling is not implemented.
set -uo pipefail
# -e is NOT set: describe-scaling-activities and others may be unimplemented,
# and one missing API must be reported, not abort the whole report.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"
source "$REPO_ROOT/configs/course.env" 2>/dev/null || true
OUT="$REPO_ROOT/outputs/lab-06-scaling-report.json"

if ! TARGETS=$(aws application-autoscaling describe-scalable-targets --service-namespace ecs --output json 2>&1); then
  echo "Application Auto Scaling is not available on this endpoint:"
  echo "  $(echo "$TARGETS" | tail -1)"
  echo '{"available": false, "targets": []}' > "$OUT"
  exit 0
fi

echo "$TARGETS" | python3 -c '
import json, sys, subprocess
d = json.load(sys.stdin)
ts = [t for t in d.get("ScalableTargets", []) if t["ResourceId"].split("/")[1:2] and t["ResourceId"].split("/")[1].startswith("usms-")]
if not ts:
    print("no usms-* scalable targets registered")
for t in ts:
    rid = t["ResourceId"]
    s = t.get("SuspendedState") or {}
    mn, mx = t["MinCapacity"], t["MaxCapacity"]
    cluster, svc = rid.split("/")[1], rid.split("/")[2]
    desired = json.loads(subprocess.run(["aws","ecs","describe-services","--cluster",cluster,"--services",svc,"--output","json"],capture_output=True,text=True).stdout or "{}").get("services",[{}])[0].get("desiredCount","?")
    pols = json.loads(subprocess.run(["aws","application-autoscaling","describe-scaling-policies","--service-namespace","ecs","--resource-id",rid,"--output","json"],capture_output=True,text=True).stdout or "{}").get("ScalingPolicies",[])
    # Order matters: PINNED (cannot scale) > FROZEN (switched off, even if at the ceiling,
    # the real problem is that nothing CAN move) > AT-CEILING > AT-FLOOR > ELASTIC
    if mn == mx: v = "PINNED"
    elif any(s.values()): v = "FROZEN"
    elif desired == mx: v = "AT-CEILING"
    elif desired == mn and len(pols) > 1: v = "AT-FLOOR"
    else: v = "ELASTIC"
    print(f"{rid}   {t[\"ScalableDimension\"]}")
    print(f"  bounds  min={mn} max={mx} desired={desired}  {v}")
    print(f"  suspended  {\", \".join(k for k,x in s.items() if x) or \"none\"}")
    for p in pols:
        print(f"  {p[\"PolicyType\"]:<22} {p[\"PolicyName\"]}")
'
echo "$TARGETS" > "$OUT"
