#!/usr/bin/env bash
# Classify every subnet in usms-vpc as PUBLIC / PRIVATE / ISOLATED,
# based purely on its route table's default route target.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$REPO_ROOT/configs/course.env"
source "$REPO_ROOT/configs/lab-02.env" 2>/dev/null || true

VPC_ID="${USMS_VPC_ID:?USMS_VPC_ID not set — source configs/lab-02.env first}"

SUBNET_IDS=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'Subnets[].SubnetId' \
  --output text)

for s in $SUBNET_IDS; do
  name=$(aws ec2 describe-subnets --subnet-ids "$s" \
          --query 'Subnets[0].Tags[?Key==`Name`]|[0].Value' --output text)
  cidr=$(aws ec2 describe-subnets --subnet-ids "$s" \
          --query 'Subnets[0].CidrBlock' --output text)
  az=$(aws ec2 describe-subnets --subnet-ids "$s" \
          --query 'Subnets[0].AvailabilityZone' --output text)

  rt=$(aws ec2 describe-route-tables \
        --filters "Name=association.subnet-id,Values=$s" \
        --query "RouteTables[?Associations[?SubnetId=='$s']].RouteTableId | [0]" \
        --output text)

  if [ -z "$rt" ] || [ "$rt" = "None" ]; then
    printf '%-24s %-14s %-12s ISOLATED no route table\n' "$name" "$cidr" "$az"
    continue
  fi

  target=$(aws ec2 describe-route-tables --route-table-ids "$rt" \
        --query 'RouteTables[0].Routes[?DestinationCidrBlock==`0.0.0.0/0`].GatewayId | [0]' \
        --output text)
  nat_target=$(aws ec2 describe-route-tables --route-table-ids "$rt" \
        --query 'RouteTables[0].Routes[?DestinationCidrBlock==`0.0.0.0/0`].NatGatewayId | [0]' \
        --output text)

  if [ -n "$target" ] && [ "$target" != "None" ] && [[ "$target" == igw-* ]]; then
    printf '%-24s %-14s %-12s PUBLIC   via %s\n' "$name" "$cidr" "$az" "$target"
  elif [ -n "$nat_target" ] && [ "$nat_target" != "None" ] && [[ "$nat_target" == nat-* ]]; then
    printf '%-24s %-14s %-12s PRIVATE  via %s\n' "$name" "$cidr" "$az" "$nat_target"
  else
    printf '%-24s %-14s %-12s ISOLATED no default route\n' "$name" "$cidr" "$az"
  fi
done
