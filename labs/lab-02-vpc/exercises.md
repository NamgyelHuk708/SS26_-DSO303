# Lab 2 Independent Exercises Report

---

## Exercise 1: A Third Public Subnet

### What Was Done
`usms-public-subnet-c` was created using the same command pattern as the other public subnets, with a new CIDR block, Availability Zone, and tags.

- Auto-assign public IPv4 was turned on
- The subnet was associated with `usms-public-rt`
- It was **not** added to `configs/lab-02.env`, since it exists only for practice

### Verification
- The subnet appears in `us-east-1c` with `Public: True`
- `usms-public-rt` shows one more association than before

![Exercise 1](LAB_2(image)/exercise_1.png)

---

## Exercise 2: A Bastion Security Group

### What Was Done
- `usms-bastion-sg` was created with one inbound rule allowing SSH from a single `/32` address
- A new SSH rule was added to `usms-app-sg`, sourced from `usms-bastion-sg` instead of a CIDR block
- The old CIDR-based SSH rule was removed using its rule ID

### Limitation Found
When a security group rule references another group instead of a CIDR block, Floci accepts the command and returns a rule ID, but does not actually save the source.

- Reading the rule back shows it empty
- This was confirmed **right after creation**, not just on a later read — so it's a **write-time issue** in Floci, not a display bug
- Plain CIDR rules save correctly every time
- The design itself is still correct and would work as expected on real AWS

### Verification
| Stage | `usms-app-sg` SSH Rule Source |
|---|---|
| Before | `10.0.0.0/16` |
| After | `usms-bastion-sg` (one rule) |

- `usms-bastion-sg` shows one inbound rule from the `/32` address

![Exercise 2 Before](LAB_2(image)/exercise_2(before).png)

![Exercise 2 After](LAB_2(image)/exercise_2(after).png)

---

## Exercise 3: A Network Report Script

### What Was Done
`scripts/utilities/lab-02-network-report.sh` checks each subnet's route table and reads its default route target:

| Route Target Prefix | Classification |
|---|---|
| `igw-` | PUBLIC |
| `nat-` | PRIVATE |
| *(no default route)* | ISOLATED |

The script resolves its own location with `${BASH_SOURCE[0]}`, so it works from any directory.

### Design Note
The script uses `set -uo pipefail`, but **not** `-e`. Without a route table, some lookups return empty — adding `-e` would stop the script instead of labelling that subnet ISOLATED and moving on.

### Verification
The script was run from the project root and again from the home folder using its full path. Both runs gave identical output.

![Exercise 3](LAB_2(image)/exercise_3.png)

---

## Exercise 4: Design and Defend Exam Results Service

### Design

**Subnet**
The service goes in the existing private tier, alongside the database. It needs the same reachability the database already has — no inbound path from the internet, outbound access for patching. A new subnet would only duplicate what already exists.

**Security Groups**
`usms-exam-sg` was created with one inbound rule:
- TCP on the service's port
- Allowed only from `10.10.0.0/16` (the campus VPN range)
- Never opened to `0.0.0.0/0`
- Outbound stays at the default allow-all, since the subnet's routing and NACL already limit what can leave

**NACL**
No change was made. `usms-private-nacl` already allows:
- Outbound HTTPS for patching
- Return traffic on ephemeral ports
- PostgreSQL inside the VPC

Since the security group already restricts access tightly, a dedicated NACL rule felt unnecessary here — though a stricter design could still add one as extra insurance.

**Second NAT Gateway**
Right now there's one NAT gateway, in AZ-a — a single point of failure for AZ-b's private subnet.

| Item | Cost |
|---|---|
| NAT gateway (hourly) | ~$0.045/hour (~$32–33/month) |
| Data processed | ~$0.045/GB |
| Second gateway in AZ-b | Roughly doubles the above |

For a university-scale system, this design accepts the single point of failure for now to keep costs down, but that should be revisited if uptime requirements change.

**Teardown Order**
1. Remove `usms-public-subnet-c` first — it was only for Exercise 1 practice and nothing depends on it. Reversible, no effect on later labs.
2. Then follow `lab-02-cleanup.sh`'s order:
   NAT gateway → Elastic IP → VPC endpoint → route table associations → route tables → NACL → security groups (`usms-db-sg`, `usms-exam-sg`, `usms-bastion-sg` before `usms-app-sg`, since they reference it) → subnets → internet gateway → VPC

### Implementation
`usms-exam-sg` was created with one inbound rule — TCP 8443 from `10.10.0.0/16`, with a description.

### Verification
The rule reads back correctly: port 8443, sourced from `10.10.0.0/16`. Unlike the group-referenced rules in Exercise 2, this one uses a plain CIDR block, so it saved with no issues.

![Exercise 4](LAB_2(image)/exercise_4.png)

---

## Exercise 5: Completing the Second Availability Zone

### What Was Done
- The developer role was assumed again, and `get-caller-identity` confirmed the session was running as `assumed-role/usms-developer-role` before anything was created
- `usms-private-subnet-b` was created with the same tagging pattern as subnet A, associated with `usms-private-rt`, and had `usms-private-nacl` applied to it

### Precaution Taken
Taking the first result (`Associations[0]`) when reading back a NACL or route table isn't reliable once more than one subnet is attached — it can return the wrong one. This had already caused a problem earlier in the lab with the private NACL. To avoid repeating it, the lookup here was filtered specifically by subnet ID.

The normal identity was restored right after the subnet was set up, since the developer role only lasts up to an hour and there's no reason to hold it longer than needed. `configs/lab-02.env` was then regenerated to pick up the new subnet's ID.

### Second Limitation Found
Even after correctly tagging the private NACL, filtering `describe-network-acls` by that tag still returned the default NACL instead.

- Reading all NACLs back **without** a server-side tag filter, then filtering the results afterward, showed the tag was there and correct
- So this is Floci's server-side tag filtering being unreliable specifically for NACLs
- The correct NACL ID was set directly in `configs/lab-02.env` as a workaround

### Verification
- `get-caller-identity` was checked both after assuming the role (`assumed-role/usms-developer-role`) and after restoring identity (`root`)
- After regenerating the env file, `USMS_PRIVATE_SUBNET_B` held a real subnet ID instead of `None`
- `verify-lab-02.sh` passed the "no empty values" check

**Remaining failures (expected/explained):**
1. The group-referenced SG rule issue from Exercise 2 (a confirmed Floci limitation)
2. A check flagging `outputs/.gitkeep` as a tracked secret — a harmless placeholder file, not an actual secret

![Exercise 5 Before](LAB_2(image)/exercise_5(before).png)
![Exercise 5 After](LAB_2(image)/exercise_5(after).png)

---

## Summary

All five exercises were completed:

| Exercise | Outcome |
|---|---|
| 1 | Added a third public subnet for practice |
| 2 | Moved SSH access to a dedicated bastion security group; surfaced a Floci limitation with group-referenced rules |
| 3 | Produced a script that classifies subnets by their actual routing behaviour, not their names or tags |
| 4 | Worked through a full design before building only the part that was asked for |
| 5 | Finished the private tier's second Availability Zone; uncovered a second Floci limitation around NACL tag filtering |

Together, these exercises covered writing security rules by reference, building a portable script, reasoning through a design with real trade-offs and costs, and working around a tool's limitations instead of assuming every failed check is a mistake.