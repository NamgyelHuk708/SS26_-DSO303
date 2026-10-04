#!/usr/bin/env bash
# Classifies every running USMS instance as REACHABLE / UNREACHABLE / NO-ADDRESS
# using only route-table and security-group data. No hard-coded IDs.
set -uo pipefail
# NOTE: -e is intentionally NOT set. Several aws calls below are expected to
# return "None" (not an error) for fields like PublicIpAddress on private
# instances, and one failed lookup should not abort the whole report.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"
source "$REPO_ROOT/configs/course.env" 2>/dev/null || true

INSTANCE_IDS=$(aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=USMS" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].InstanceId' --output text)

printf '%-16s %-14s %-15s %-12s %s\n' "NAME" "PRIVATE-IP" "PUBLIC-IP" "VERDICT" "REASON"

for id in $INSTANCE_IDS; do
  NAME=$(aws ec2 describe-instances --instance-ids "$id" \
    --query 'Reservations[0].Instances[0].Tags[?Key==`Name`]|[0].Value' --output text)
  [ "$NAME" = "None" ] && NAME="$id"

  PRIVATE_IP=$(aws ec2 describe-instances --instance-ids "$id" \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
  PUBLIC_IP=$(aws ec2 describe-instances --instance-ids "$id" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

  SUBNET=$(aws ec2 describe-instances --instance-ids "$id" \
    --query 'Reservations[0].Instances[0].SubnetId' --output text)
  SG=$(aws ec2 describe-instances --instance-ids "$id" \
    --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' --output text)

  IGW_ROUTE=$(aws ec2 describe-route-tables \
    --filters "Name=association.subnet-id,Values=$SUBNET" \
    --query 'RouteTables[0].Routes[?DestinationCidrBlock==`0.0.0.0/0`].GatewayId | [0]' \
    --output text 2>/dev/null || echo "None")

  HAS_IGW_ROUTE=false
  case "$IGW_ROUTE" in igw-*) HAS_IGW_ROUTE=true ;; esac

  SG_ALLOWS_80=$(aws ec2 describe-security-groups --group-ids "$SG" \
    --query 'SecurityGroups[0].IpPermissions[?FromPort==`80`].IpRanges[0].CidrIp | [0]' \
    --output text 2>/dev/null || echo "None")

  if [ "$PUBLIC_IP" = "None" ] || [ -z "$PUBLIC_IP" ]; then
    if [ "$HAS_IGW_ROUTE" = true ]; then
      VERDICT="NO-ADDRESS"; REASON="igw route present but no public address"
    else
      VERDICT="UNREACHABLE"; REASON="no igw route on subnet"
    fi
  else
    if [ "$HAS_IGW_ROUTE" = true ] && [ "$SG_ALLOWS_80" != "None" ]; then
      VERDICT="REACHABLE"; REASON="igw route + sg allows 80/tcp from $SG_ALLOWS_80"
    else
      VERDICT="UNREACHABLE"; REASON="has address but igw route or sg rule missing"
    fi
  fi

  printf '%-16s %-14s %-15s %-12s %s\n' "$NAME" "$PRIVATE_IP" "$PUBLIC_IP" "$VERDICT" "$REASON"
done
