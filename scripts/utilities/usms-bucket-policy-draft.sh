#!/usr/bin/env bash
# USMS bucket policy DRAFT (Lab 09 Exercise 5). Applies NOTHING.
#
# Reads the Step 4 inventory and every customer managed policy that names the transcripts bucket, works out
# which role (or user) ARNs are granted any s3: action on it, and writes outputs/lab-09-bucket-policy-draft.json:
#   1. Allow  - each of those principals, limited to the s3: actions it ALREADY has
#   2. Deny   - EVERY principal ("*") when aws:SecureTransport is false
#   3. Deny   - every principal OTHER than those principals and the account root (NotPrincipal)
# The bucket name is DERIVED from Lab 01's policy document - never typed. Works whether or not the bucket exists.
# No access key is read or referenced anywhere.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"
# shellcheck disable=SC1090
source configs/course.env 2>/dev/null || true
# shellcheck disable=SC1090
source configs/lab-01.env 2>/dev/null || true
ACCOUNT="${USMS_ACCOUNT_ID:-000000000000}"
INVENTORY="outputs/lab-09-identity-inventory.json"
[ -f "$INVENTORY" ] || { echo "no $INVENTORY - run Lab 09 Step 4 first" >&2; exit 2; }

# The bucket ARN comes from the first bucket-level Resource in Lab 01's read/write policy.
RW_ARN="${USMS_POLICY_S3_RW:-arn:aws:iam::$ACCOUNT:policy/USMSStudentDataReadWrite}"
RW_VER=$(aws iam get-policy --policy-arn "$RW_ARN" --query 'Policy.DefaultVersionId' --output text)
BUCKET_ARN=$(aws iam get-policy-version --policy-arn "$RW_ARN" --version-id "$RW_VER" --output json \
  | python3 -c 'import json,sys
d=json.load(sys.stdin)["PolicyVersion"]["Document"]
sts=d["Statement"] if isinstance(d["Statement"],list) else [d["Statement"]]
for s in sts:
    for r in (s["Resource"] if isinstance(s["Resource"],list) else [s["Resource"]]):
        if r.startswith("arn:aws:s3:::") and "/" not in r:
            print(r); raise SystemExit')
# Parameter expansion: strip the fixed ARN prefix to get the bare bucket name without another tool or
# another API call - "${var#prefix}" removes the shortest match of prefix from the front.
BUCKET="${BUCKET_ARN#arn:aws:s3:::}"
[ -n "$BUCKET" ] || { echo "could not derive the bucket name from $RW_ARN" >&2; exit 2; }

TMP="${TMPDIR:-/tmp}/usms-bp-$$"; mkdir -p "$TMP"; trap 'rm -rf "$TMP"' EXIT
aws iam list-policies --scope Local --output json > "$TMP/policies.json"
python3 - "$TMP" "$BUCKET" > "$TMP/naming.txt" << 'PY'
import json, sys, subprocess
tmp, bucket = sys.argv[1], sys.argv[2]
for p in json.load(open(f"{tmp}/policies.json"))["Policies"]:
    out = subprocess.run(["aws","iam","get-policy-version","--policy-arn",p["Arn"],"--version-id",p["DefaultVersionId"],
                          "--output","json"], capture_output=True, text=True)
    if out.returncode == 0 and f"arn:aws:s3:::{bucket}" in out.stdout:
        json.dump({"arn": p["Arn"], "name": p["PolicyName"],
                   "document": json.loads(out.stdout)["PolicyVersion"]["Document"]}, open(f"{tmp}/{p['PolicyName']}.json","w"))
        print(p["PolicyName"])
PY
for name in $(cat "$TMP/naming.txt"); do
  aws iam list-entities-for-policy --policy-arn "arn:aws:iam::$ACCOUNT:policy/$name" --output json > "$TMP/$name.entities.json"
done

python3 - "$TMP" "$BUCKET" "$ACCOUNT" "$INVENTORY" << 'PY'
import json, sys, os, datetime
tmp, bucket, account, inv_path = sys.argv[1:5]
B, O = f"arn:aws:s3:::{bucket}", f"arn:aws:s3:::{bucket}/*"
names = open(f"{tmp}/naming.txt").read().split()
inv = {r["role"]: r["arn"] for r in json.load(open(inv_path))}
L = lambda x: x if isinstance(x, list) else [x]
grants, policy_roles = {}, {}
for n in names:
    doc = json.load(open(f"{tmp}/{n}.json"))["document"]
    ent = json.load(open(f"{tmp}/{n}.entities.json"))
    arns = [inv.get(r["RoleName"], f"arn:aws:iam::{account}:role/{r['RoleName']}") for r in ent.get("PolicyRoles", [])]
    arns += [f"arn:aws:iam::{account}:user/{u['UserName']}" for u in ent.get("PolicyUsers", [])]
    policy_roles[n] = arns
    acts = {a for s in L(doc["Statement"]) if s["Effect"] == "Allow"
            for a in L(s["Action"]) if a.startswith("s3:")
            if any(r in (B, O) or r.startswith(B + "/") for r in L(s["Resource"]))}
    for a in arns:
        grants.setdefault(a, set()).update(acts)
stmts = []
for i, (arn, acts) in enumerate(sorted(grants.items()), 1):
    stmts.append({"Sid": f"AllowExisting{i}", "Effect": "Allow", "Principal": {"AWS": arn},
                  "Action": sorted(acts), "Resource": [B, O]})
stmts.append({"Sid": "DenyInsecureTransport", "Effect": "Deny", "Principal": "*", "Action": "s3:*",
              "Resource": [B, O], "Condition": {"Bool": {"aws:SecureTransport": "false"}}})
stmts.append({"Sid": "DenyEveryoneElse", "Effect": "Deny",
              "NotPrincipal": {"AWS": sorted(grants) + [f"arn:aws:iam::{account}:root"]},
              "Action": "s3:*", "Resource": [B, O]})
draft = {"Version": "2012-10-17", "Statement": stmts}
json.dump(draft, open("outputs/lab-09-bucket-policy-draft.json", "w"), indent=2)

# mechanical checks
bad = [s["Sid"] for s in stmts if "Principal" in s and s["Principal"] == "*" and s["Sid"] != "DenyInsecureTransport"]
bad += [s["Sid"] for s in stmts if isinstance(s.get("Principal"), dict)
        and not all(str(p).startswith("arn:aws:iam::") for p in L(s["Principal"]["AWS"]))]
text = json.dumps(draft)
print("principal check :", "OK - every Principal is an ARN, '*' only on DenyInsecureTransport" if not bad else f"FAIL {bad}")
print("resource check  :", "OK - bucket ARN with and without /*" if (f'"{B}"' in text and f'"{O}"' in text) else "FAIL")

with open("outputs/lab-09-lab10-readiness.txt", "w") as f:
    f.write(f"# Lab 09 -> Lab 10 readiness - {datetime.datetime.now(datetime.timezone.utc).isoformat()}\n")
    f.write(f"bucket name (read from USMSStudentDataReadWrite) : {bucket}\n")
    f.write(f"policies naming the bucket                       : {', '.join(names)}\n")
    for n in names:
        f.write(f"  {n:<26} -> {', '.join(policy_roles[n]) or '(attached to nothing)'}\n")
    f.write(f"principals granted access                        : {len(grants)}\n")
    f.write("when Lab 10 runs create-bucket                  : every principal above gains real access at that\n"
            "  instant (their policies already name the bucket); nobody else does, and this draft - once the S3\n"
            "  lab applies it - would additionally refuse plain-HTTP requests and every principal not listed.\n")
print(open("outputs/lab-09-lab10-readiness.txt").read())
PY
