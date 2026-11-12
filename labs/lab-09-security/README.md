# AWS Practical Laboratory Report

**Tools used:** Floci 2.4.0 (local AWS emulator, Docker Compose, hybrid storage), AWS CLI v1, python3, jq, Docker, git

**Floci support path: A.** `simulate-principal-policy` answered on this build, so Step 9 has a simulated answer as well as a read one. Floci still **enforces** nothing: every proof in this lab is a readback of a document or a rule.

---

## 1. Aim / Objective

The aim of this practical is to review the USMS system built in Labs 1 to 6 on both access-control axes – who can call what (IAM) and what can reach what (security groups and routing) – and repair what the review finds. On the identity side: inventory and audit every role, split a read-only transcripts policy from Lab 1's read/write one, add confused-deputy conditions to a trust policy, scope `iam:PassRole`, put a permissions boundary on a new deployment role, narrow a session with a session policy, rotate an access key with no outage, and require IMDSv2. On the network side: audit every security group, write egress rules on three groups, narrow SSH to a bastion group, and prove the data tier is unreachable through several independent controls. Finally, prove every control survives a restart and that no earlier lab's verification changed, and save the results to `configs/lab-09.env`.

## 2. Introduction

Every AWS request is decided twice. An **API call** is decided by IAM – identity policies, permissions boundaries, session policies and resource policies – and fails with an error that names an action. A **packet** is decided by routing, security groups and network ACLs, and fails with a timeout. Neither axis knows the other exists, so a request needs a yes from both. This lab reviews both axes, fixes identity before network, and adds rather than replaces wherever a later lab depends on a resource.

### Key Features

- **Trust policy vs identity policy:** the trust policy decides *who may become* a role; the identity policy decides *what it may do*
- **Confused deputy protection:** `aws:SourceAccount` and `aws:SourceArn` conditions on a service-principal trust
- **Scoped `iam:PassRole`:** named role ARNs plus `iam:PassedToService`, closing the classic privilege-escalation path
- **Permissions boundary:** a ceiling that grants nothing; effective permissions are the intersection
- **Session policy:** a third intersection, set by the caller at assume time
- **Access key rotation:** create → move → deactivate → delete, with no window in which nothing works
- **IMDSv2:** tokens required, hop limit 1 – SSRF and container defences
- **Written egress and group-referenced rules:** rules about roles in the architecture, not about addresses
- **Defence in depth:** a negative ("the database is unreachable") proven by enumerating independent controls

## 3. Use Case

USMS holds the academic record of every student. The review must show who can read and write transcripts, close the paths an attacker would use, and do it without changing what the system does.

| Need | How it is met |
|---|---|
| A reporting task must read transcripts but never change them | `USMSStudentDataReadOnly` on a new `usms-transcripts-reader-role`, with an explicit Deny on every write |
| No other account may trick ECS into using our task role | `aws:SourceAccount` + `aws:SourceArn` conditions on `usms-ecs-task-role` (and in Exercise 2 on ecs-exec and lambda) |
| The deployment pipeline must not be able to escalate | `usms-deploy-role`: PassRole to 3 named roles, only to ECS tasks, Deny to EC2, capped by `USMSPermissionsBoundary` |
| A leaked long-lived key must have a short life | `usms-dev-01`'s key rotated with no outage |
| An SSRF bug in the web app must not leak its credentials | IMDSv2 required, hop limit 1, on `usms-web-01` |
| A compromised database must not be able to send data anywhere it likes | written egress: tcp/443 only |
| SSH must not be reachable from every task in the VPC | tcp/22 on `usms-app-sg` from `usms-bastion-sg` only |

## 4. System Architecture / Design

![Lab 09 architecture](LAB_09(image)/architecture.png)

The left column is the identity axis (roles, their trust and permissions, the users who assume them, and the transcripts bucket with its Exercise 5 policy draft). The VPC is the network axis, and the security groups on the right carry the rules exactly as they stand after this lab. In the simulator the request Students → IGW → ALB → enrolment tasks returns **200**, and changing `usms-enrolment-sg` to admit only `usms-app-sg` returns **403 – blocked by Security Group**, so the diagram really models the group-referenced rules. (The simulator evaluates inbound rules only, so removing an egress rule does not change its result.)

## 5. Implementation Procedure

I recorded a baseline of five earlier verification scripts, probed the build (Path A), and inventoried the account's 10 roles into a JSON file that an IAM audit script turned into findings (HIGH=8, MED=36). I split a read-only transcripts policy from Lab 1's, attached it to a new reader role, and rewrote the ECS task role's trust with confused-deputy conditions. I created a permissions boundary, a deploy policy with a scoped `iam:PassRole` and a deploy role that wears the boundary; narrowed a developer session with a session policy and computed the intersection by hand and with the simulator; rotated `usms-dev-01`'s access key in four steps; and required IMDSv2 on the web instance. On the network side, a security-group audit (HIGH=4, MED=11) led me to write egress on three groups, narrow SSH to the bastion group, and build a reachability matrix and a five-control negative proof for the database. A Floci restart then proved persistence and that the five earlier verification scripts were unchanged. I wrote `configs/lab-09.env`, ran the verification script, and committed. Along the way I found and fixed several bugs in the lab's own checks (Section 7), and restored two group-referenced rules that the previous Floci version had lost.

## 6. Results and Evidence

### 6.1 CLI Output

Environment and role-name fix

![Step 1](LAB_09(image)/1.png)

*Account 000000000000; my lab-01.env stores three roles as ARNs, so I derived the names; 17 values present*

---

Security baseline

![Step 2.1](LAB_09(image)/2.1.png)

*lab-02 31/2, lab-03 33/3, lab-04 38/1, lab-05 46/3, lab-06 24/18 – every failure a known Floci limitation, listed by name*

---

Why the instances do not start

![Step 2.2](LAB_09(image)/2.2.png)

*`Error starting EC2 container … 404 No such container` – Floci kept Lab 03's container IDs, which the 2.4.0 upgrade removed*

---

Identity inventory

![Step 4.1](LAB_09(image)/4.1.png)

*10 roles (5 the lab expects, 2 Lab 01 exercise roles, 2 EKS roles, 1 foreign `wine-mlops` role), 5 users, USMSStudentDataReadWrite attached 3 times*

---

Inventory JSON and trust policies

![Step 4.2](LAB_09(image)/4.2.png)

*Every role without a boundary; ec2-app-role trusts a service, developer-role trusts a named user*

---

IAM audit

![Step 5](LAB_09(image)/5.png)

*HIGH=8 (unconditioned service trust on 8 roles) MED=36, exit code 1*

---

The transcripts policy

![Step 6](LAB_09(image)/6.png)

*ListBucket + GetBucketLocation; Get + Put + **DeleteObject**; Deny DeleteBucket. Three roles carry it; the bucket does not exist yet (404)*

---

Read-only policy and reader role

![Step 7.1](LAB_09(image)/7.1.png)

*`USMSStudentDataReadOnly` with an explicit Deny on every write, and `usms-transcripts-reader-role` with the scoped trust*

---

The confused-deputy fix

![Step 7.2](LAB_09(image)/7.2.png)

*SAME PRINCIPAL, NEW CONDITION on usms-ecs-task-role*

---

Boundary, deploy policy and role

![Step 8.1](LAB_09(image)/8.1.png)

*The permissions boundary read back correctly – the 2.0.1 Known Issue does not occur on 2.4.0*

---

Scoped PassRole

![Step 8.2](LAB_09(image)/8.2.png)

*PassRole to 3 named roles, ecs-tasks only, plus a Deny to EC2; the boundary attached to nothing*

---

The intersection

![Step 9.1](LAB_09(image)/9.1.png)

*Three Describe actions ALLOWED, `s3:GetObject` NOT in the identity policy -> denied*

---

The simulator as a second opinion

![Step 9.2](LAB_09(image)/9.2.png)

*ec2:DescribeVpcs allowed, sts:GetCallerIdentity allowed, iam:CreateUser **explicitDeny** – matches the documents; identity back to root*

---

Access key rotation – before

![Step 10.1](LAB_09(image)/10.1.png)

*One key, Active, created in Lab 01*

---

Access key rotation – during

![Step 10.2](LAB_09(image)/10.2.png)

*Two keys, the old one Inactive, and the profile still working*

---

Access key rotation – after

![Step 10.3](LAB_09(image)/10.3.png)

*One key, created today; no other key file in outputs/*

---

IMDSv2

![Step 11](LAB_09(image)/11.png)

*optional -> required, hop limit 1 – IMDSv2 REQUIRED, HOP LIMIT 1; IMDS disabled on usms-db-01*

---

Security group audit

![Step 12](LAB_09(image)/12.png)

*HIGH=4 MED=11 LOW=5 across 8 groups; usms-db-sg and usms-enrolment-sg showing no ingress (lost group references)*

---

Enrolment egress – the revoke that did nothing

![Step 13](LAB_09(image)/13.png)

*Two tcp/443 rules authorised; `revoke` returned True but the `-1` rule was still there*

---

Enrolment egress – fixed

![Step 13 fixed](LAB_09(image)/13(fixed).png)

*Revoked by rule ID with a corrected filter; only the two tcp/443 rules remain*

---

ALB egress to a group

![Step 14](LAB_09(image)/14.png)

*Out: tcp/80 to usms-enrolment-sg, CIDR null – Floci 2.4.0 stores group references*

---

Data tier egress

![Step 15](LAB_09(image)/15.png)

*Three groups with 0 allow-all egress rules, counted with the corrected query*

---

SSH – before the cutover

![Step 16.1](LAB_09(image)/16.1.png)

*Three SSH rules: from 10.0.0.0/16, a broken empty-source rule, and the new one from usms-bastion-sg*

---

SSH – after

![Step 16.2](LAB_09(image)/16.2.png)

*One SSH rule, from the bastion group; 80/443 unchanged*

---

Reachability matrix

![Step 17.1](LAB_09(image)/17.1.png)

*Two internet-facing groups; four instances, including two Lab 03 leftovers wearing usms-db-sg*

---

The negative proof

![Step 17.2](LAB_09(image)/17.2.png)

*usms-db-01: no public IP, no auto-assign, default route to the NAT, no CIDR source, custom NACL*

---

Persistence

![Step 18.1](LAB_09(image)/18.1.png)

*IDs re-derived from the API, all ten facts identical – PERSISTENCE PROVEN*

---

Nothing broke

![Step 18.2](LAB_09(image)/18.2.png)

*All five earlier verification scripts identical to the baseline – NOTHING BROKE*

---

Kubernetes after the restart

![Step 18.3](LAB_09(image)/18.3.png)

*The k3s cluster survived this restart (3d10h old); rebuild helper ran, SMOKE TEST PASSED*

---

configs/lab-09.env

![Step 19](LAB_09(image)/19.png)

*16 exports, every value populated, no access key ID*

---

First verification run

![Step 20.1](LAB_09(image)/20.1.png)

*PASS=47 FAIL=3: two lost group-referenced rules and one false positive on an IAM variable*

---

Final verification

![Step 20.3](LAB_09(image)/20..3.png)

*PASS=50 FAIL=0 after restoring the two rules and fixing the false positive*

---

The exercise screenshots are in [`Exercise.md`](Exercise.md).

### 6.2 AWS Console Verification

Floci has no console. Everything was verified by readback: `get-role`, `get-policy-version`, `list-entities-for-policy`, `describe-security-group-rules`, `describe-instances` and `simulate-principal-policy`, plus four scripts (`usms-iam-audit.sh`, `usms-sg-audit.sh`, `usms-reachability-matrix.sh`, `verify-lab-09.sh`). On real AWS the same evidence would come from the IAM console (role trust relationships, the Access Advisor tab, IAM Access Analyzer) and the VPC console (security group inbound/outbound rules), with CloudTrail recording who made each change.

## 7. Analysis and Discussion

**What the review fixed.** Three trust policies gained confused-deputy conditions (one in the lab, two in Exercise 2) without changing their principals; transcripts now have a read-only path; the pipeline has a role that cannot escalate; the one long-lived key was rotated; IMDSv2 is required; four security groups have written egress; SSH comes only from the bastion tier; and the system's behaviour did not change (NOTHING BROKE).

**Bugs I found in the lab's own checks.** The most valuable part of this lab turned out to be that **"True" and "0" are not evidence**:

| Bug | Effect | Fix |
|---|---|---|
| `IpProtocol==\`-1\`` compares with the **number** -1; AWS stores the **string** "-1" | a check for "no allow-all egress" counts 0 even when the rule is there (proved: 0 vs 1 on usms-db-sg) | `` `"-1"` `` |
| `length(IpPermissionsEgress…)` on `describe-security-groups` | the field is inside `SecurityGroups[0]`; the query errors, hidden by `2>/dev/null` | add `SecurityGroups[0].` (4 queries in verify) |
| `revoke-security-group-egress --ip-permissions` restating the rule | returned **True** and removed nothing | revoke by `--security-group-rule-ids` and read back |
| `'SecurityGroups[0].GroupId \| [0]'` | `\| [0]` on a string is null – would have created a duplicate bastion group | drop `\| [0]` |
| "boundary attached to NOTHING" check | nested quotes turn `\| [0]` into a shell pipe – can never pass | `list-entities-for-policy` |
| "no unexpanded variable" check | flags any `$`, including Lab 01's IAM variable `${aws:username}` | flag only `$` + an uppercase name |

**Floci 2.4.0 vs 2.0.1.** Several Known Issues are fixed on 2.4.0: permissions boundaries and IMDS options read back, group-referenced rules are stored, `simulate-principal-policy` evaluates policies (it returned `explicitDeny` for `iam:CreateUser`, matching the documents), and the k3s cluster survives a restart. The group-referenced **ingress** rules created under 2.0.1 had been stored with empty sources; I restored the two that verify depends on after Step 18 (so the regression comparison stayed honest) and removed nine broken leftovers. As a side effect verify-lab-04 reached 39/0 for the first time.

**What is still open (and recorded, not hidden).** `usms-app-sg` is a second internet-facing entry point (Exercise 4); tcp/443 to `0.0.0.0/0` still allows an HTTPS exfiltration (needs hostname filtering); two Lab 03 instances still wear `usms-db-sg`; five confused-deputy findings are accepted with reasons; and a role from another project (`wine-mlops-…`) lives in this account.

**Floci vs real AWS.**

| | Real AWS | This build |
|---|---|---|
| IAM evaluation on every call | yes | **no** – any credentials accepted |
| Simulation | `simulate-principal-policy`, Access Analyzer | both answer on 2.4.0 |
| Security groups on traffic | every packet | **no traffic** – rules stored only |
| IMDSv2 | enforced at the hypervisor | stored only; instances cannot even start |
| Detection (CloudTrail, GuardDuty) | available | not available – every control here is preventive |

## 8. Reflection

**What I learned.** The two-axis model finally made sense: an error that names an action is IAM, a hang is the network, and neither answers for the other. I also learned that a permissions boundary *grants nothing*, that a trust policy is more dangerous than an identity policy, and that a security claim about what *cannot* happen can only be proven by reading documents and listing independent controls – which is exactly why a broken check is so dangerous.

**Challenges.** The hardest moment was Step 13: a revoke that said `True`, a lookup that found nothing, and a second revoke that also said `True` – while the rule was still there. Tracing that to a JMESPath number-vs-string comparison, and then finding the same bug and a missing `SecurityGroups[0]` in the lab's verification script, taught me to distrust success messages. The upgraded Floci also meant my instances could not start, and I had to show from Floci's own log that this was not something Lab 09 had caused.

**Real-world use.** On a real account I would run `usms-iam-audit.sh` and `usms-sg-audit.sh` on every change, keep an accepted-findings file with reasons instead of silencing findings, replace the long-lived key with IAM Identity Center, and add the detective half (CloudTrail, AWS Config, GuardDuty) that Floci cannot show.

**Next.** Removing the second front door (Exercise 4), interface endpoints and hostname filtering for egress, and applying the Exercise 5 bucket policy once Lab 10 has created the bucket.

## 9. Conclusion

The review covered both axes. Identity: a read-only policy and role, confused-deputy conditions on three roles, a scoped `iam:PassRole` and a permissions boundary on a new deploy role, a session-policy intersection, an outage-free key rotation, and IMDSv2. Network: written egress on four groups, SSH only from the bastion tier, a reachability matrix and a five-control proof that the database is unreachable. Persistence was proven across a restart, the five earlier verification scripts did not change, and `verify-lab-09.sh` passes 50 of 50 after documented fixes – including fixes to bugs in the lab's own checks that would otherwise have reported success when it was not true.

## 10. Appendix

### Additional Files

- `policies/`: `usms-student-data-ro-policy.json`, `trust-ecs-tasks-scoped.json`, `usms-permissions-boundary.json`, `usms-deploy-policy.json`, `trust-deploy.json`, `usms-enrolment-sg-egress.json`, `usms-alb-sg-egress.json`, `usms-db-sg-egress.json`, `usms-egress-allow-all.json` (the undo), `usms-app-sg-ssh-bastion.json`; Exercises: `usms-app-sg-egress.json`, `trust-breakglass.json`, `usms-breakglass-policy.json`, `trust-lambda-scoped.json`, `usms-iam-accepted-findings.json`
- `scripts/utilities/`: `usms-iam-audit.sh`, `usms-sg-audit.sh`, `usms-reachability-matrix.sh`, `verify-lab-09.sh`, `usms-eks-rebuild.sh`, `usms-exposure-report.sh`, `usms-bucket-policy-draft.sh`
- `scripts/cleanup/lab-09-cleanup.sh` (written, not run)
- `configs/lab-09.env`, `notes/lab-09-notes.md`, `labs/lab-09-security/Exercise.md`
- Simulator: `USMS Lab 09 - security review.json`

### Submission Checklist

- [x] Objectives stated
- [x] Introduction provided
- [x] Real-world use case described
- [x] Tools listed
- [x] System design included
- [x] Implementation documented
- [x] CLI outputs included
- [x] Console verification addressed (Floci has no console, see 6.2)
- [x] Analysis completed
- [x] Reflection completed
- [x] Conclusion written