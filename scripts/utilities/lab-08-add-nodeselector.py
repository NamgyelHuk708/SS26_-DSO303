#!/usr/bin/env python3
"""Lab 08 Step 11 - record nodeSelector workload=usms in manifests/lab-07/20-enrolment.yaml.

The lab's inline script looks for 'spec:' followed directly by 'containers:'. In this repo
Lab 07 Exercise 4 put topologySpreadConstraints in between, so that script would match
nothing. This version handles both layouts and says clearly if it changed anything.
"""
import os, sys
root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
p = os.path.join(root, "manifests", "lab-07", "20-enrolment.yaml")
s = open(p).read()
if "nodeSelector" in s:
    print("nodeSelector already present in", p); sys.exit(0)
for anchor in ("    spec:\n      topologySpreadConstraints:", "    spec:\n      containers:\n        - name: enrolment"):
    if anchor in s:
        s = s.replace(anchor, anchor.replace("    spec:\n", "    spec:\n      nodeSelector:\n        workload: usms\n", 1), 1)
        open(p, "w").write(s)
        print("nodeSelector workload=usms added to", p); sys.exit(0)
print("ANCHOR NOT FOUND - file not changed:", p); sys.exit(1)
