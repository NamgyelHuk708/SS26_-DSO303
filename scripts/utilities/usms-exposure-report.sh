#!/usr/bin/env bash
# USMS exposure report (Lab 09 Exercise 3).
#
# One line per network interface in usms-vpc:  name  private  public  VERDICT  reason
# The verdict is computed ONLY from: the interface's subnet route table (is there a 0.0.0.0/0 route to an
# internet gateway?), its public address, and its security groups' ingress rules. Never from names, tags or
# descriptions - those are used only to LABEL the line.
#
# Verdicts:
#   EXPOSED   public address AND the subnet routes 0.0.0.0/0 to an igw-.  Defended choice for an interface with no
#             ingress rule at all (e.g. a NAT gateway): still EXPOSED - the internet can address it and the packets
#             would be routed; the security group is then the ONLY control left, one rule change from open. The
#             reason column says "no ingress rule at all" so the reader sees why it is not currently reachable.
#   ISOLATED  no igw route on the subnet, or no public address - the internet has no path or no address.
#
# Read-only. No arguments. Works from any directory. Also writes outputs/lab-09-exposure.json.
#
# set -uo pipefail but NOT -e: one failed lookup (a security group that has been deleted, a subnet with no explicit
# association) must not abort the whole report - each lookup falls back and the line says what was unknown.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1090
source "$REPO_ROOT/configs/course.env" 2>/dev/null || true
# shellcheck disable=SC1090
source "$REPO_ROOT/configs/lab-02.env" 2>/dev/null || true
VPC="${USMS_VPC_ID:-}"
[ -n "$VPC" ] || { echo "USMS_VPC_ID not set - is configs/lab-02.env present?" >&2; exit 2; }

TMP="${TMPDIR:-/tmp}/usms-exposure-$$"           # $$ keeps two runs from colliding
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT                          # cleaned up even if python fails

aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$VPC" --output json > "$TMP/eni.json" || echo '{"NetworkInterfaces":[]}' > "$TMP/eni.json"
aws ec2 describe-route-tables      --filters "Name=vpc-id,Values=$VPC" --output json > "$TMP/rt.json"  || echo '{"RouteTables":[]}'       > "$TMP/rt.json"
aws ec2 describe-security-groups   --filters "Name=vpc-id,Values=$VPC" --output json > "$TMP/sg.json"  || echo '{"SecurityGroups":[]}'    > "$TMP/sg.json"
aws ec2 describe-instances         --filters "Name=vpc-id,Values=$VPC" --output json > "$TMP/ec2.json" || echo '{"Reservations":[]}'      > "$TMP/ec2.json"

python3 - "$TMP" "$REPO_ROOT/outputs/lab-09-exposure.json" << 'PY'
import json, sys, os, datetime
tmp, out_json = sys.argv[1], sys.argv[2]
L = lambda f: json.load(open(os.path.join(tmp, f)))
enis   = L("eni.json").get("NetworkInterfaces", [])
rts    = L("rt.json").get("RouteTables", [])
sgs    = {g["GroupId"]: g for g in L("sg.json").get("SecurityGroups", [])}
insts  = {i["InstanceId"]: i for r in L("ec2.json").get("Reservations", []) for i in r.get("Instances", [])}

# subnet -> route table: the explicit association wins, otherwise the VPC's MAIN route table
explicit, main = {}, None
for rt in rts:
    for a in rt.get("Associations", []):
        if a.get("Main"):
            main = rt
        elif a.get("SubnetId"):
            explicit[a["SubnetId"]] = rt

def igw_route(subnet):
    rt = explicit.get(subnet, main)
    if rt is None:
        return None, "no route table found"
    how = "explicit" if subnet in explicit else "main"
    for r in rt.get("Routes", []):
        if r.get("DestinationCidrBlock") == "0.0.0.0/0" and str(r.get("GatewayId", "")).startswith("igw-"):
            return True, f"igw route ({how} rt)"
    return False, f"no igw route ({how} rt)"

def ingress(groups):
    """(set of 'proto/port from src' that admit the internet, total rule count, unknown group ids)"""
    open_rules, total, unknown = [], 0, []
    for g in groups:
        sg = sgs.get(g)
        if sg is None:
            unknown.append(g); continue
        for p in sg.get("IpPermissions", []):
            proto = "all" if p.get("IpProtocol") == "-1" else p.get("IpProtocol")
            port = "all" if p.get("FromPort") is None else str(p["FromPort"])
            n = len(p.get("IpRanges", [])) + len(p.get("UserIdGroupPairs", [])) + len(p.get("PrefixListIds", []))
            total += n
            for r in p.get("IpRanges", []):
                if r.get("CidrIp") == "0.0.0.0/0":
                    open_rules.append(f"{proto}/{port}")
    return open_rules, total, unknown

def label(e):
    att = e.get("Attachment") or {}
    iid = att.get("InstanceId")
    if iid:
        i = insts.get(iid)
        state = (i or {}).get("State", {}).get("Name", "gone")
        name = {t["Key"]: t["Value"] for t in (i or {}).get("Tags", [])}.get("Name", iid)
        return name if state != "terminated" else f"{name} (TERMINATED - lingering eni)", state
    desc = e.get("Description") or ""
    t = e.get("InterfaceType") or ""
    return (desc[:28] or t or e["NetworkInterfaceId"]), ("detached" if not att else att.get("Status", "?"))

rows = []
for e in sorted(enis, key=lambda x: x.get("PrivateIpAddress", "")):
    name, state = label(e)
    priv = e.get("PrivateIpAddress", "-")
    pub = (e.get("Association") or {}).get("PublicIp")
    groups = [g["GroupId"] for g in e.get("Groups", [])]
    route, route_why = igw_route(e.get("SubnetId"))
    open_rules, total, unknown = ingress(groups)
    if route and pub:
        verdict = "EXPOSED"
        if open_rules:
            why = f"{route_why} + sg allows {','.join(sorted(set(open_rules)))} from 0.0.0.0/0"
        elif total == 0:
            why = f"{route_why}, but no ingress rule at all"
        else:
            why = f"{route_why}, ingress only from groups/private ranges"
    else:
        verdict = "ISOLATED"
        why = route_why if not route else "no public address"
    if unknown:
        why += f" (unknown group {','.join(unknown)})"
    rows.append({"interface": e["NetworkInterfaceId"], "name": name, "state": state, "private": priv,
                 "public": pub, "subnet": e.get("SubnetId"), "groups": groups, "verdict": verdict, "reason": why})
    print(f"{name[:30]:<31} {priv:<15} {(pub or '-'):<15} {verdict:<9} {why}")

print()
print(f"{sum(r['verdict']=='EXPOSED' for r in rows)} EXPOSED, {sum(r['verdict']=='ISOLATED' for r in rows)} ISOLATED, {len(rows)} interfaces")
os.makedirs(os.path.dirname(out_json), exist_ok=True)
json.dump({"generated_at": datetime.datetime.now(datetime.timezone.utc).isoformat(), "interfaces": rows},
          open(out_json, "w"), indent=2)
PY
