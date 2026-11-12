# Lab 9 Independent Exercises

---

## Exercise 1: Finish the Egress Work on the Web Tier

### What I did
I wrote `policies/usms-app-sg-egress.json` with an **unquoted** heredoc (`<< EOF`), because four values had to be expanded at write time – the S3 prefix list and three security-group IDs – and a security-group document contains no IAM variable that must survive. I authorised the six rules **first** and only then revoked the default rule by its rule ID, so there was never a moment when the web tier could initiate nothing at all (no credential refresh, no DNS). Ingress was not touched.

| # | Requirement | Rule | Why this destination |
|---|---|---|---|
| 1 | S3 for transcripts, through the gateway endpoint | tcp/443 → `pl-63a5400a` | the managed prefix list behind Lab 02's endpoint – traffic stays on the AWS network |
| 2 | AWS endpoints, incl. STS for the instance profile | tcp/443 → `0.0.0.0/0` | no interface endpoints on this build |
| 3 | the enrolment API | tcp/80 → **`usms-alb-sg`** | since Lab 05 the API is reached through the load balancer, not the tasks |
| 4 | the database | tcp/5432 → **`usms-db-sg`** | |
| 5 | name resolution | **udp/53** and **tcp/53** → `10.0.0.2/32` | the Amazon resolver is the VPC base + 2, one of the five addresses AWS reserves (Lab 02). UDP carries normal queries; TCP is the fallback for answers too large for UDP, so both are needed |

### Result
The audit no longer reports "egress is the DEFAULT allow-all rule" for usms-app-sg; the matrix shows its six destinations; ingress still has three rules (80, 443, 22 from the bastion group); and `verify-lab-09.sh` still reports **PASS=50 FAIL=0**.

![Exercise 1 - rules](LAB_09(image)/ex1.1.png)

![Exercise 1 - audit, matrix and verify](LAB_09(image)/ex1.2.png)

**169.254.169.254** needs no rule: it is link-local and answered by the hypervisor on the instance itself, so that traffic never passes through a security group.

**usms-bastion-sg is different in kind.** A jump host exists to *initiate* administrative connections, so its egress is its purpose rather than a side effect. It should be **tcp/22 → `usms-app-sg`** (the tier it administers) and nothing else, instead of allow-all.

---

## Exercise 2: The Break-Glass Role, and the Findings This Lab Left Open

### Part A – `usms-breakglass-role`

| Requirement | How it is met |
|---|---|
| assumable only by usms-admin-01 | `Principal: {"AWS": "arn:aws:iam::000000000000:user/usms-admin-01"}` |
| MFA required | `"Bool": {"aws:MultiFactorAuthPresent": "true"}` |
| deliberate | `"StringEquals": {"sts:ExternalId": "usms-breakglass-suspend-scaling"}` |
| shortest maximum session | `--max-session-duration 3600` – the minimum IAM allows for this setting; a caller can still ask for less with `--duration-seconds` |
| a permissions boundary | `USMSPermissionsBoundary` |
| only the calls Lab 06 used to suspend scaling | `USMSBreakGlassScaling`: `application-autoscaling:RegisterScalableTarget` (with `--suspended-state`) and `DescribeScalableTargets` – no wildcard actions |

**AND or OR?** Both conditions sit in **one** Condition block under different operators (`Bool`, `StringEquals`), and IAM requires every operator in a block to be true – they combine with **AND**. (Several values for the *same* key would be OR.)

**What `sts:ExternalId` buys inside one account.** Normally it protects a third party from a confused-deputy attack across accounts. Here it buys **deliberateness**: the caller must supply a value nobody types by accident, so a script, a stale console role-switch link or a habit cannot assume the break-glass role without meaning to.

`Resource: "*"` remains on the two actions and the audit reports it as MED; `RegisterScalableTarget` is narrowed in practice by the `--resource-id` the caller passes. I accept that MED with that reason.

![Exercise 2 - break-glass role](LAB_09(image)/ex2.1.png)

### Part B – the open confused-deputy findings

| Role | Decision | Reason |
|---|---|---|
| usms-ecs-exec-role | **fixed** | same scoped ECS trust as Step 7 (`aws:SourceAccount` + `aws:SourceArn arn:aws:ecs:…`) |
| usms-lambda-exec-role | **fixed** | `aws:SourceAccount` + `aws:SourceArn arn:aws:lambda:us-east-1:000000000000:function:*` |
| usms-ec2-app-role | **accepted** | EC2 sends no `aws:SourceArn` when an instance profile delivers credentials, so such a condition would deny every instance. Compensating: IMDSv2 + hop limit 1, and the deploy policy's Deny on passing roles to EC2 |
| usms-backup-operator-role | accepted | same EC2 limitation (Lab 01 exercise role) |
| usms-eks-node-role | accepted | EKS nodes are EC2 instances; out of scope until IRSA exists |
| usms-eks-cluster-role | accepted | Lab 07 role, out of Lab 09's scope by the lab's own statement |
| wine-mlops-PredictFunctionRole-… | accepted | not a USMS resource – another project shares this Floci account; its owner must remove it |

The decisions live in `policies/usms-iam-accepted-findings.json` (committed), **one reason per entry**. I patched `usms-iam-audit.sh` to read it: a HIGH finding with a matching, reasoned entry is printed as `ACCEPTED` with its reason; an entry **without** a reason is ignored (so the file cannot become a silent suppression list); the script still exits 1 for any HIGH that is not accepted.

![Exercise 2 - trust readbacks](LAB_09(image)/ex2.2.png)

After re-inventorying (the audit reads the inventory, which had to be refreshed after the changes):

![Exercise 2 - audit with accepted findings](LAB_09(image)/ex2.3.png)

**HIGH=0 MED=40 ACCEPTED=5 roles=13, exit code 0** – an audit that reports decisions, not silence.

---

## Exercise 3: The Exposure Report

`scripts/utilities/usms-exposure-report.sh` prints one line per network interface in usms-vpc and writes `outputs/lab-09-exposure.json`. The verdict is computed only from the interface's **subnet route table** (a `0.0.0.0/0` route to an `igw-`), its **public address**, and its **security groups' ingress** – names and tags only label the line.

```
ECS task arn:aws:ecs:us-east    10.0.3.10       -               ISOLATED  no igw route (explicit rt)
ECS task arn:aws:ecs:us-east    10.0.3.11       -               ISOLATED  no igw route (explicit rt)
usms-db-01                      172.27.0.4      -               ISOLATED  no igw route (explicit rt)
usms-web-01                     172.27.0.4      127.0.0.1       EXPOSED   igw route (explicit rt) + sg allows tcp/443,tcp/80 from 0.0.0.0/0
usms-db-01                      172.27.0.5      -               ISOLATED  no igw route (explicit rt)
usms-db-02                      172.27.0.7      -               ISOLATED  no igw route (explicit rt)
1 EXPOSED, 5 ISOLATED, 6 interfaces
```

It produced **identical output** from `~` and from `labs/lab-09-security/`, and was unchanged by Exercise 1 – the verdict uses ingress, routes and addresses, while egress controls what an interface can *start*, not what can reach it.

| Constraint | How it is handled |
|---|---|
| any directory, no arguments, no hard-coded IDs | `REPO_ROOT` from `${BASH_SOURCE[0]}`; the VPC from `configs/lab-02.env` |
| a group that is not cached / no longer exists | the line says `(unknown group sg-…)` instead of crashing |
| an interface with no description | labelled by its interface type or ID |
| a subnet with no explicit route-table association | falls back to the VPC's **main** route table, and says so |
| a lingering interface of a terminated instance | labelled `(TERMINATED - lingering eni)` and still judged on its rules |
| `set -uo pipefail` without `-e` | one failed lookup must not abort the whole report |
| a public interface with no ingress rule at all | **EXPOSED** – the internet can address it and the packets would be routed; the security group is then the *only* control, one rule change from open. The reason column says "no ingress rule at all" |

(All five edge cases were tested against stub data before running it on Floci.)

**A finding the two tools disagree on.** Step 17's matrix showed the two Lab 03 database leftovers with `public=127.0.0.1`; this report shows them with no public address. The matrix reads the **instance's** `PublicIpAddress`, this report reads the **interface's** `Association.PublicIp`. On Floci, 127.0.0.1 is a published Docker port on the instance record, not an address on the interface. A verdict should always say which field it read.

![Exercise 3](LAB_09(image)/ex3.png)

---

## Exercise 4: The Security Review, Written for Someone Else to Act On

### 1. The second front door

`usms-app-sg` admits tcp/80 and tcp/443 from `0.0.0.0/0` to **usms-web-01**, a public instance with an Elastic IP. It was the front door in Lab 02 Step 14, before the load balancer existed; since Lab 05 the enrolment API is served through `usms-enrolment-alb`, so this is a **second, older** entry point that no later lab argued for. It should not stay reachable. Moving it behind the load balancer means: a target group for the instance on port 80, a listener rule on the existing listener (for example path `/portal*`), changing `usms-app-sg` ingress from `0.0.0.0/0` to **`usms-alb-sg`** only, adding tcp/80 to `usms-app-sg` in the load balancer's egress, and finally releasing the Elastic IP. What would break: anything that bookmarks the instance's public address, and anything that relies on reaching the instance directly over HTTPS (TLS would move to the load balancer).
*The other side:* a single instance is simpler to operate than a target group, and the load balancer is itself one shared component whose misconfiguration would now take down both paths at once.

### 2. What restricting egress actually bought

Prevented: (1) **DNS-tunnel exfiltration** from the database or tasks (no udp/53 except to the resolver on the web tier); (2) a compromised task opening **SSH, database or SMTP connections** to other hosts or the internet; (3) a **reverse shell or command-and-control channel on a non-443 port**. Not prevented: (1) **an HTTPS POST of the data to any host** – tcp/443 to `0.0.0.0/0` is still allowed; (2) **abuse of an allowed AWS endpoint** – for example copying data into an attacker's own S3 bucket over the same 443 path. Closing those needs hostname- or endpoint-level control: **AWS Network Firewall** with a domain allow-list (about US$0.395 per endpoint-hour plus US$0.065 per GB processed in us-east-1 – https://aws.amazon.com/network-firewall/pricing/), or **VPC endpoint policies** on S3 and interface endpoints for ECR, Logs and STS (about US$0.01 per endpoint-hour per AZ plus data – https://aws.amazon.com/privatelink/pricing/). *Prices to be checked on the pricing pages at the time of the review.*

### 3. Who can read or write a transcript

| Principal | How it gets access | Read | Write | Granting document |
|---|---|---|---|---|
| usms-ec2-app-role | instance profile on usms-web-01 | yes | **yes (Put + Delete)** | USMSStudentDataReadWrite |
| usms-ecs-task-role | the enrolment tasks' task role | yes | **yes (Put + Delete)** | USMSStudentDataReadWrite |
| usms-eks-node-role | **every pod** on the EKS nodes | yes | **yes (Put + Delete)** | USMSStudentDataReadWrite |
| usms-transcripts-reader-role | a future reporting task | yes | no (explicit Deny) | USMSStudentDataReadOnly |
| (nobody) | USMSReportingReadOnly names `transcripts/*` but is attached to nothing | – | – | USMSReportingReadOnly |
| usms-admin-01 | **indirectly** – USMSAssumeAppRoles lets it assume app roles | via a role | via a role | USMSAssumeAppRoles |
| account root | always | yes | yes | – |

**How I know it is complete.** The real-AWS answer is **IAM Access Analyzer** (and `get-account-authorization-details` for the whole account in one call). The lab expected neither to work locally; on Floci 2.4.0 **both answered**, so I used `get-account-authorization-details` to scan every role, user and group in one dump for any attached or inline policy that names the bucket. It found the same three policies and the same four principals as the per-policy `list-entities-for-policy` lookups – two independent methods agreeing. What it still cannot show: resource policies (none exist yet – the bucket does not exist) and access gained by assuming a role, which is why the admin's indirect path is listed separately.

![Exercise 4 - access evidence](LAB_09(image)/ex4.png)

### 4. Knowing when something changes

Everything in this lab is **preventive**; none of it tells us when someone tries. I would add, in order: **AWS CloudTrail** (one management-event trail is free; S3 storage is the cost – https://aws.amazon.com/cloudtrail/pricing/) to record every IAM and security-group change; **AWS Config** rules for "security group allows 0.0.0.0/0" and "role without boundary" (about US$0.003 per configuration item recorded – https://aws.amazon.com/config/pricing/); **Amazon GuardDuty** for unusual `AssumeRole`, credential use from new places and known-bad destinations (priced per event volume – https://aws.amazon.com/guardduty/pricing/); and **IAM Access Analyzer** for external-access findings (free). On the morning after an incident I would read, in order: CloudTrail for `AssumeRole`, `CreateAccessKey`, `UpdateAssumeRolePolicy`, `AuthorizeSecurityGroup*` and `PutBucketPolicy` in the window; then GuardDuty findings; then VPC Flow Logs for unexpected egress; then the S3 data events on the transcripts bucket.

### The command sequence to move the web tier behind the load balancer (written, not run)

1. Create the target group.
   ```bash
   aws elbv2 create-target-group --name usms-web-tg --protocol HTTP --port 80 --vpc-id "$USMS_VPC_ID" \
     --target-type instance --health-check-path /health.json
   ```
2. Register the instance.
   ```bash
   aws elbv2 register-targets --target-group-arn "$WEB_TG_ARN" --targets Id="$USMS_WEB_INSTANCE"
   ```
3. Add a listener rule (priority 20, below the existing rule 10).
   ```bash
   aws elbv2 create-rule --listener-arn "$USMS_ALB_LISTENER_ARN" --priority 20 \
     --conditions Field=path-pattern,Values='/portal*' --actions Type=forward,TargetGroupArn="$WEB_TG_ARN"
   ```
4. Let the load balancer reach the web tier.
   ```bash
   aws ec2 authorize-security-group-egress --group-id "$USMS_ALB_SG" \
     --ip-permissions "[{\"IpProtocol\":\"tcp\",\"FromPort\":80,\"ToPort\":80,\"UserIdGroupPairs\":[{\"GroupId\":\"$USMS_APP_SG\"}]}]"
   aws ec2 authorize-security-group-ingress --group-id "$USMS_APP_SG" \
     --ip-permissions "[{\"IpProtocol\":\"tcp\",\"FromPort\":80,\"ToPort\":80,\"UserIdGroupPairs\":[{\"GroupId\":\"$USMS_ALB_SG\"}]}]"
   ```
5. Remove the public HTTP and HTTPS rules.
   > **What will be deleted:** the two `0.0.0.0/0` ingress rules on usms-app-sg (80 and 443).
   > **What depends on it:** anyone reaching usms-web-01 directly by its public address.
   > **Reversible?** Yes – one `authorize-security-group-ingress` each.
   > **Effect on later labs:** none if step 3's rule serves the same pages.
   ```bash
   aws ec2 revoke-security-group-ingress --group-id "$USMS_APP_SG" --security-group-rule-ids "$RULE_80" "$RULE_443"
   ```
6. Release the Elastic IP.
   > **What will be deleted:** the instance's public address (usms-web-eip).
   > **What depends on it:** any DNS record or bookmark pointing at that address.
   > **Reversible?** No – the same address cannot be guaranteed again.
   > **Effect on later labs:** none; the portal is now reached through the load balancer's DNS name.
   ```bash
   aws ec2 disassociate-address --association-id "$EIP_ASSOC_ID"
   aws ec2 release-address --allocation-id "$USMS_WEB_EIP_ALLOC"
   ```

---

## Exercise 5: The Bucket Policy the S3 Configuration Lab Will Apply

`scripts/utilities/usms-bucket-policy-draft.sh` applies nothing. It:

- derives the bucket name from **Lab 01's policy document** (the first bucket-level `Resource` of USMSStudentDataReadWrite), then strips the fixed prefix with a parameter expansion – `BUCKET="${BUCKET_ARN#arn:aws:s3:::}"` – which needs no extra tool or API call (the comment in the script says so). `grep -c usms-student-data` on the script prints **0**: the name is never typed.
- finds **every** customer-managed policy that names the bucket (three: ReadWrite, ReadOnly, ReportingReadOnly) and the principals of each through `list-entities-for-policy`
- writes `outputs/lab-09-bucket-policy-draft.json`: one **Allow** per principal limited to the actions it already has; a **Deny** for every principal (`"*"`) when `aws:SecureTransport` is false; and a **Deny** with `NotPrincipal` listing those roles and the account root
- checks it mechanically: every `Principal` is an ARN except on the insecure-transport Deny, and the bucket ARN appears with and without `/*`
- writes `outputs/lab-09-lab10-readiness.txt` (bucket name, the three policy names, their role ARNs, the principal count and what changes when Lab 10 creates the bucket)

`USMS_BUCKET_POLICY_DRAFT` was appended to `configs/lab-09.env`, which now has **17** exports. No script contains, reads or references an access key (`grep -ci 'AKIA\|access.key'` prints 0).

![Exercise 5](LAB_09(image)/ex5.png)

**The two Denies.** `USMSStudentDataReadOnly`'s Deny is an *identity* policy, so it can only stop the actions of the one role it is attached to, whatever the bucket says. The draft's Deny is a *resource* policy on the bucket, so it stops **every** caller – plain-HTTP requests from anyone, and any principal not on the list, including one that is later given a broad identity policy. An identity policy in this account is never consulted for a principal in another account, but a bucket policy always is – so only the resource-policy Deny protects the transcripts from a cross-account caller.

---

## Summary

| Exercise | Result |
|---|---|
| 1 | usms-app-sg egress written: S3 prefix list, 443, 80 → alb-sg, 5432 → db-sg, DNS udp+tcp → 10.0.0.2; verify still 50/0 |
| 2 | usms-breakglass-role (MFA AND ExternalId, 3600 s, boundary, two actions); ecs-exec and lambda trusts fixed; 5 findings accepted with reasons; audit HIGH=0, exit 0 |
| 3 | exposure report from routes + addresses + ingress; 1 EXPOSED, 5 ISOLATED; identical from two directories |
| 4 | four-part review: second front door, what egress control bought, a complete transcripts access table (two methods agree), detection plan, and the un-run command sequence |
| 5 | computed bucket policy draft, readiness file, 17 exports, and the identity-vs-resource Deny contrast |