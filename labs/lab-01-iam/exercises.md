
# Exercise 5 — Prepare Lab 2 policy (v3)
Note: this exercise was initially skipped, then completed after revisiting
the lab.

Compared v2's BuildNetworkingForLab02 actions against the 11 actions Lab 2
needs. Missing: ec2:CreateNatGateway and ec2:AllocateAddress (a NAT Gateway
requires an Elastic IP, hence AllocateAddress is required alongside it).
Created v3 via create-policy-version with --set-as-default, adding only
those 2 actions. Verified v1/v2/v3 all still exist, v3 is now default.
Added USMS_VPC_CIDR=10.0.0.0/16 to configs/lab-01.env for Lab 2 to consume.
Updated verify-lab-01.sh's expected default version from v2 to v3 to match
the current, correct state.
