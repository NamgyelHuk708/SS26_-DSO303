#!/usr/bin/env bash
# USMS edge-readiness report (Lab 10 Exercise 3).
#
# Emits ONE JSON document on stdout: every Lambda function whose name starts with "usms-", with
# name, runtime, memory, timeout, published versions, aliases, env_vars and edge_eligible.
# Diagnostics go to stderr only, so `usms-edge-report.sh | python3 -m json.tool` always works.
#
# edge_eligible is true only when ALL of these hold:
#   - runtime is Node.js or Python               (the only two Lambda@Edge accepts)
#   - no environment variables                    (forbidden at the edge)
#   - no VPC configuration                        (forbidden at the edge)
#   - at least one published version              (the edge refuses $LATEST and aliases)
#   - memory <= 128 MB and timeout <= 5 s         if the name contains "viewer" (viewer-trigger caps)
#     memory <= 10240 MB and timeout <= 30 s      otherwise                    (origin-trigger caps)
# "reasons" lists every rule a function breaks, so a false is never unexplained.
#
# No hard-coded function list. Runs from any directory.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT/configs/course.env" 2>/dev/null || true

TMP="${TMPDIR:-/tmp}/usms-edge-report-$$"
mkdir -p "$TMP"; trap 'rm -rf "$TMP"' EXIT

# One call returns most of the configuration for every function.
if ! aws lambda list-functions --output json > "$TMP/functions.json" 2> "$TMP/err"; then
  echo "usms-edge-report: list-functions failed: $(cat "$TMP/err")" >&2
  echo "[]"; exit 1
fi

# Per-function counts need two more calls each; names come from the listing, never from this file.
python3 -c "
import json
for f in json.load(open('$TMP/functions.json')).get('Functions', []):
    if f['FunctionName'].startswith('usms-'):
        print(f['FunctionName'])" > "$TMP/names"

while read -r fn; do
  aws lambda list-versions-by-function --function-name "$fn" --output json > "$TMP/$fn.versions.json" 2>/dev/null \
    || { echo "usms-edge-report: cannot list versions of $fn" >&2; echo '{"Versions":[]}' > "$TMP/$fn.versions.json"; }
  aws lambda list-aliases --function-name "$fn" --output json > "$TMP/$fn.aliases.json" 2>/dev/null \
    || { echo "usms-edge-report: cannot list aliases of $fn" >&2; echo '{"Aliases":[]}' > "$TMP/$fn.aliases.json"; }
done < "$TMP/names"
echo "usms-edge-report: $(wc -l < "$TMP/names" | tr -d ' ') usms- function(s) found" >&2

python3 - "$TMP" << 'PY'
import json, sys, os
tmp = sys.argv[1]
names = open(f"{tmp}/names").read().split()
funcs = {f["FunctionName"]: f for f in json.load(open(f"{tmp}/functions.json")).get("Functions", [])}
report = []
for n in sorted(names):
    f = funcs[n]
    versions = [v for v in json.load(open(f"{tmp}/{n}.versions.json")).get("Versions", []) if v.get("Version") != "$LATEST"]
    aliases = json.load(open(f"{tmp}/{n}.aliases.json")).get("Aliases", [])
    env = (f.get("Environment") or {}).get("Variables") or {}          # absent key -> {} (no set -u trap in Python)
    vpc = (f.get("VpcConfig") or {}).get("SubnetIds") or []
    runtime, mem, timeout = f.get("Runtime", ""), f.get("MemorySize", 0), f.get("Timeout", 0)
    viewer = "viewer" in n
    cap_mem, cap_t = (128, 5) if viewer else (10240, 30)
    reasons = []
    if not runtime.startswith(("nodejs", "python")): reasons.append(f"runtime {runtime} not supported at the edge")
    if env:                 reasons.append(f"{len(env)} environment variable(s)")
    if vpc:                 reasons.append("VPC configuration")
    if not versions:        reasons.append("no published version")
    if mem > cap_mem:       reasons.append(f"memory {mem} MB > {cap_mem} MB ({'viewer' if viewer else 'origin'} cap)")
    if timeout > cap_t:     reasons.append(f"timeout {timeout} s > {cap_t} s ({'viewer' if viewer else 'origin'} cap)")
    report.append({"name": n, "runtime": runtime, "memory": mem, "timeout": timeout,
                   "versions": len(versions), "aliases": len(aliases), "env_vars": bool(env),
                   "edge_eligible": not reasons, "reasons": reasons})
print(json.dumps(report, indent=2))
PY
