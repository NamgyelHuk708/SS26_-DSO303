# Lab 09 notes

## Support path
Path A - full: simulate-principal-policy answered on Floci 2.4.0, so Step 9 can use it as a second opinion. Floci still enforces nothing - every proof is read from documents.
Floci 2.4.0 (auto-upgraded from 2.0.1 before Lab 08).

## Bucket
usms-student-data did NOT exist when I ran Step 6 (head-bucket failed) - Lab 10 creates it.

## Environment: EC2 instances do not start on Floci 2.4.0
aws ec2 start-instances returns pending, but usms-web-01 and usms-db-01 fall back to stopped.
docker logs floci: "Error starting EC2 container <id>: Status 404: No such container" - Floci kept the
container IDs from Lab 03, and those containers were removed when Floci upgraded to 2.4.0. Fixing it would
mean relaunching (new instance IDs that lab-03.env depends on), so I left them stopped. This explains the
lab-03 baseline failures. Lab 09 changes only configuration, so it is unaffected; the baseline and Step 18
both have the instances stopped.

## Step 4 - inventory
10 roles: the lab's 5, two from Lab 01 exercises (usms-analytics-partner-role, usms-backup-operator-role),
two from Lab 07 (usms-eks-cluster-role, usms-eks-node-role - out of scope here), and
wine-mlops-PredictFunctionRole-ffd3430bbaec, which belongs to a different project that used the same Floci
account - an identity no USMS owner can account for, which on a real account would be a finding in itself.
USMSReportingReadOnly has 0 attachments (a leftover). No role has a permissions boundary.

Your turn - two trust policies:
usms-ec2-app-role trusts a SERVICE principal (ec2.amazonaws.com): no person assumes it - any EC2 instance launched
with usms-ec2-app-profile receives its credentials automatically from the instance metadata service, so whoever can
launch an instance with that profile (or reach that instance's metadata) can obtain them.
usms-developer-role trusts an AWS identity (user/usms-dev-01): only that named user can call sts:AssumeRole with their
own long-lived access key, so obtaining these credentials means having usms-dev-01's key.

## Step 5 - IAM audit: HIGH=8 MED=36 roles=10 (exit 1)
- 8 HIGH, all the same shape: a service principal trusted with no Condition (confused deputy) on ec2-app,
  ecs-exec, ecs-task, lambda, backup-operator, both EKS roles and the foreign wine-mlops role.
  The lab expected 4; the extra four come from Lab 01's exercises, Lab 07 and the other project.
  A convention repeated across roles, not one mistake.
- USMSDeveloperBase allows mutating EC2 calls on Resource "*", including ec2:DeleteVpc - the right verbs on
  any noun. Lab 01 wrote it to teach the idea, not to be minimal.
- No role has a permissions boundary.
- usms-analytics-partner-role has no HIGH: its trust is an AWS principal, not a service principal.
- Fixed in this lab: usms-ecs-task-role (Step 7). Exercise 2: ecs-exec, lambda, ec2-app.
  Out of scope: the EKS roles (no IRSA on this build) and wine-mlops (not a USMS resource).

## Step 6 - the transcripts policy
USMSStudentDataReadWrite v1: s3:ListBucket + s3:GetBucketLocation on the bucket; s3:GetObject + s3:PutObject +
s3:DeleteObject on bucket/*; explicit Deny on s3:DeleteBucket. Carried by THREE roles (ec2-app, ecs-task,
eks-node). head-bucket: 404, exit 255 - the bucket does not exist yet.

Your turn:
- To display a transcript the enrolment API needs: s3:ListBucket, s3:GetBucketLocation, s3:GetObject.
  (ListBucket matters: without it, a missing key returns 403 AccessDenied instead of 404 NoSuchKey.)
- To store one the registry's upload workflow needs: the same three + s3:PutObject.
- The single action in the second list and not the first: s3:PutObject.
- Extra finding: s3:DeleteObject is in NEITHER list - no USMS workload needs it, yet three roles carry it,
  so a compromised task could delete every transcript. The read-only policy (Step 7) explicitly denies it.

## Step 7 - read-only split and the confused-deputy fix
- USMSStudentDataReadOnly: Allow s3:ListBucket + s3:GetObject; explicit Deny on PutObject, DeleteObject,
  DeleteBucket, PutBucketPolicy. The Deny adds nothing today, but still wins if someone later attaches a broader
  policy to the same role - that is why it is there, not redundancy.
- usms-transcripts-reader-role: scoped ecs-tasks trust + the read-only policy.
- usms-ecs-task-role: trust rewritten - SAME PRINCIPAL, NEW CONDITION (aws:SourceAccount + aws:SourceArn).
  Its permissions (USMSStudentDataReadWrite) are unchanged, because Lab 10 depends on them.
- The undo is outputs/lab-09-ecs-task-role-trust-before.json.

## Step 8 - boundary, scoped PassRole, deploy role
- usms-deploy-role trusts user/usms-admin-01 and carries USMSPermissionsBoundary. The boundary READ BACK correctly
  (PermissionsBoundaryType Policy) - the Floci 2.0.1 Known Issue ("boundaries not reflected on readback") does not
  occur on 2.4.0.
- USMSDeployBase: iam:PassRole only on 3 named roles and only to ecs-tasks.amazonaws.com, plus an explicit Deny on
  passing anything to ec2.amazonaws.com. This closes the escalation at its step 1 (no Resource "*") and step 3
  (no instance can be launched with a passed role).
- USMSPermissionsBoundary is attached to NOTHING as an ordinary policy - it looks like an orphan but is the ceiling
  on usms-deploy-role. Do not tidy it up.
- Floci still enforces none of it: these are proofs about documents, not demonstrations.

## Step 9 - session policy and the intersection
- Assumed usms-developer-role from the usms-dev profile with a session policy (15 min). describe-vpcs worked
  as the scoped session. (--no-cli-pager is a CLI v2 flag; my CLI is v1, so that one line errored - harmless.)
- First attempt: all four session actions were ALLOWED, because USMSDeveloperBase v3 already allows
  sts:GetCallerIdentity. The lab's alternative s3:ListAllMyBuckets also would not work: v3 has s3:List*.
  I used s3:GetObject instead -> "NOT in the identity policy -> denied". A session policy can only
  narrow; it cannot grant what the role never had.
- Second opinion (Path A): simulate-principal-policy -> ec2:DescribeVpcs allowed, sts:GetCallerIdentity allowed,
  iam:CreateUser explicitDeny. That matches the documents: v3's DenyDangerousIdentityChanges statement denies
  iam:CreateUser, and an explicit Deny beats every Allow. Floci 2.4.0 evaluates policies in the simulator,
  but still does not ENFORCE them on real calls.
- Session credentials deleted, identity back to root.

## Step 10 - access key rotation
create (AKIAUL1W4BA870M5V206) -> move the usms-dev profile and prove it works -> deactivate the old key
(AKIAPCB5BWW4S95CANEA, created 2026-08-21 in Lab 01) and prove the profile still works -> delete it.
Step 3 (deactivate) is what makes it safe: an Inactive key can be reactivated in one call if something breaks;
a deleted one is gone. On a real system the pause between deactivate and delete would be a day or a week -
this lab compressed it to a minute. get-access-key-last-used returned N/A on Floci.
The new secret went straight to outputs/ (git-ignored by outputs/*, chmod 600), never to the screen.
On a real account a human would use IAM Identity Center / federation (temporary credentials) and workloads
would use roles, so no long-lived key would exist at all.

## Step 11 - IMDSv2
- usms-web-01: HttpTokens optional -> required, hop limit 1, endpoint enabled. Read back correctly - the Floci
  2.0.1 Known Issue (HttpTokens not reflected) does not occur on 2.4.0. Floci still runs no metadata service, so
  this is stored configuration, not an enforced control.
- What --http-tokens required prevents: an SSRF bug in the web app making a plain GET to
  169.254.169.254/.../security-credentials/ and returning the instance role's credentials. IMDSv2 needs a PUT with
  a header to get a token first, which an SSRF bug almost never controls.
- What the hop limit of 1 prevents: a different attack - a container (or anything one network hop away) on the
  instance reaching the metadata service and inheriting the host's role.
- Safe rollout order on real AWS: watch the per-instance MetadataNoToken CloudWatch metric until it reaches 0
  (no caller still uses IMDSv1 / old SDKs), THEN require tokens - otherwise old clients break.
- Your turn: usms-db-01 has no instance profile, so there are no credentials to protect: --http-endpoint disabled
  removes the metadata service entirely. Doing the same on usms-web-01 would cut off its instance-profile
  credentials, so the app could no longer call S3 (Lab 03 Step 11).

## Step 12 - security group audit: HIGH=4 MED=11 LOW=5 groups=8
| Finding | Verdict |
| --- | --- |
| usms-alb-sg ingress tcp/80 and tcp/443 from 0.0.0.0/0 | Accepted risk - internet-facing load balancer (Lab 05 Step 4) |
| usms-app-sg ingress tcp/80 and tcp/443 from 0.0.0.0/0 | Open finding - a second internet entry point that predates the ALB (Exercise 4) |
| usms-app-sg ingress tcp/22 from 10.0.0.0/16 | Fix in Step 16 - any compromised thing in the VPC can reach SSH |
| Default allow-all egress on every group | Fix in Steps 13-15 (alb, enrolment, db); Exercise 1 for usms-app-sg |
| default group, usms-exam-sg, usms-eks-cluster-sg on no interface | Accepted / out of scope - nothing uses them |

FLOCI LIMITATION found by the audit: group-referenced ingress rules are NOT stored. usms-db-sg shows no ingress
(should be tcp/5432 from usms-app-sg) and usms-enrolment-sg shows none (should be tcp/80 from usms-alb-sg).
usms-app-sg carries a "tcp/22 from <none>" rule - a group-referenced rule stored with an empty source.
This is the same cause as the verify-lab-02/04/05 failures since Lab 02. On real AWS these rules would exist;
here the data and enrolment tiers effectively admit nothing, which is stricter than intended, not looser.
Extra groups: usms-bastion-sg (Lab 02 Exercise 2) and usms-exam-sg (tcp/8443 from 10.10.0.0/16, unused).

## Step 13 - enrolment egress
S3 prefix list found: pl-63a5400a. Authorised tcp/443 -> pl-63a5400a and tcp/443 -> 0.0.0.0/0 FIRST
(sgr-1c9080cc8a4f56adb, sgr-9b8034af20a90d5cb). Final readback: only those two tcp/443 egress rules.
- revoke --ip-permissions (the undo document) returned True but REMOVED NOTHING - the -1 rule was still there.
- Looking it up with the lab's filter IpProtocol==`-1` found nothing either, and a revoke with an empty rule ID
  ALSO returned True. Revoking by rule ID (sgr-dbb34883f78737672) with a corrected filter worked.

TWO BUGS in the lab's own checks (proved on usms-db-sg, which still had its default rule):
1. Number vs string: `-1` in backticks is the JSON NUMBER -1; AWS stores IpProtocol as the STRING "-1".
   length(SecurityGroups[0].IpPermissionsEgress[?IpProtocol==`-1`])   -> 0   (wrong)
   length(SecurityGroups[0].IpPermissionsEgress[?IpProtocol==`"-1"`]) -> 1   (right)
   A check written the lab's way reports "no allow-all egress" even when the rule is there.
2. Missing path: queries like length(IpPermissionsEgress[...]) on describe-security-groups fail with
   "length() received null", because the field sits inside SecurityGroups[0]. Inside verify-lab-09.sh the
   error is hidden by 2>/dev/null, so the check simply FAILS.
I fixed both in verify-lab-09.sh (4 queries) and use the corrected form in Steps 15, 18 and 19.
Lesson: "True" is not evidence, and a count of 0 is not evidence; read the actual rules back.

## Step 14 - ALB egress to a group
Authorised tcp/80 -> usms-enrolment-sg (sgr-4de516bbe7770f4a1), then revoked the default -1 rule BY ID
(sgr-749b46c74f126086a, found with the corrected IpProtocol==`"-1"` filter). Readback: ingress 80/443 from
0.0.0.0/0 unchanged; egress ONLY tcp/80 -> sg-6ec3933aea484898c, CIDR null.
New on Floci 2.4.0: the group reference WAS stored (ReferencedGroupInfo.GroupId populated). The group-referenced
INGRESS rules from Labs 02-05 (usms-db-sg <- usms-app-sg, usms-enrolment-sg <- usms-alb-sg) were lost under
2.0.1 and are still missing - new group references work, old ones did not survive.
A group reference is a rule about a ROLE in the architecture (whatever wears usms-enrolment-sg); a CIDR would be
a rule about where the tasks happen to be today - and Lab 06's scaling changes that constantly.

## Step 15 - data tier egress
usms-db-sg egress is now tcp/443 -> 0.0.0.0/0 only (for OS updates through usms-nat). Three groups now report
0 allow-all egress rules, counted with the CORRECTED query.
What this blocks: DNS-tunnel exfiltration, SSH/RDP out, direct database-to-database connections, SMTP, and any
command-and-control channel on a port other than 443.
What it does NOT block: an HTTPS POST of the data to any host on the internet - port 443 to 0.0.0.0/0 is still
wide. Stopping that needs hostname filtering (AWS Network Firewall, or an egress proxy) - Exercise 4.
On real AWS this rule also breaks dnf update: no DNS. The VPC resolver is 10.0.0.2 (VPC base + 2), so a complete
rule set adds UDP 53 and TCP 53 to 10.0.0.2/32 - UDP first because normal queries use UDP and only fall back to
TCP for large answers (Exercise 1).

## Step 16 - SSH narrowed to the bastion group
Reused usms-bastion-sg (sg-1b4ae994286e37e81, Lab 02 Exercise 2; admits tcp/22 only from 203.0.113.10/32).
Added tcp/22 FROM sg:usms-bastion-sg on usms-app-sg FIRST, then removed by rule ID: the old tcp/22 from
10.0.0.0/16 (Lab 02 Step 14) AND a broken leftover tcp/22 rule whose source group had been lost under Floci 2.0.1.
Result: SSH to the web tier is reachable only from whatever wears the bastion group - not from every address in
the VPC, which included every Fargate task's subnet.
Lab fix: the lab's lookup 'SecurityGroups[0].GroupId | [0]' returns null (| [0] on a string), which would have
created a duplicate group; I used 'SecurityGroups[0].GroupId'.

## Step 17 - reachability matrix and the negative proof
- Internet-facing: usms-alb-sg (accepted, Lab 05) and usms-app-sg (80/443 - never argued, Exercise 4).
- usms-db-sg and usms-enrolment-sg admit NOTHING on this build (their group-referenced ingress was lost under
  Floci 2.0.1) - so the matrix cannot show them as "single point of control"; on real AWS each would be protected
  by exactly ONE rule and would be on that list. usms-bastion-sg, usms-eks-cluster-sg and usms-exam-sg are.
- Negative proof for usms-db-01 (i-79180dfeb7f1774ca): (1) no public IP, (2) subnet does not auto-assign,
  (3) 0.0.0.0/0 -> nat-a91ea2eac079855c3, no igw, (4) usms-db-sg admits no CIDR (in fact nothing), (5) custom NACL
  acl-ea22cd870b51c4d02. Review Q5: if control 3 failed, controls 1 and 4 still stop it (no address to send to,
  and nothing admitted); if control 4 failed, controls 1, 3 and 5 still stop it.
- FINDING: the matrix lists FOUR instances, not two - usms-db-02 and a SECOND usms-db-01 (Lab 03 exercise
  leftovers), both wearing usms-db-sg and both WITH a public address (127.0.0.1 is how Floci publishes one).
  The negative proof covers only the instance in lab-03.env. On real AWS those two would be a database tier
  reachable from the internet if any rule ever admitted them - they should be terminated or have their public
  addresses removed. (Private IPs show as 172.27.x - Floci's Docker network, not the VPC CIDR.)

## Step 18 - persistence and regression
- 10 facts read before and after floci-down/floci-up, every ID re-derived from the API (by group name + VPC):
  PERSISTENCE PROVEN. (The lab's Part 1 queries had the same two bugs as Step 13 - missing SecurityGroups[0]
  and `-1` as a number - so I used the corrected queries; with the originals the comparison would have
  compared error messages.)
- verify-lab-02..06 identical to the Step 2 baseline: NOTHING BROKE. The same failures before and after are
  Floci limitations recorded in Step 2, not caused by this lab.
- EC2 instances were stopped before and after (Step 1: they cannot start on 2.4.0), so no start step.
- Kubernetes: on Floci 2.4.0 the k3s cluster SURVIVED the restart (node and deployments 3d10h old, apply said
  "unchanged"). The empty cluster at the start of Lab 08 was caused by the 2.0.1 -> 2.4.0 upgrade, not by
  restarts. usms-eks-rebuild.sh re-applied everything harmlessly and the smoke test passed.

## Section 8 - verification: PASS=50 FAIL=0 (after documented fixes)
First run: PASS=47 FAIL=3.
1-2. "usms-enrolment-sg still admits tcp/80 from usms-alb-sg" and "usms-db-sg still admits tcp/5432 from usms-app-sg":
   both group-referenced ingress rules (Lab 05 Step 13, Lab 02) had been lost under Floci 2.0.1, which stored them
   with an EMPTY source. Floci 2.4.0 stores group references (proven in Steps 14 and 16), so AFTER Step 18 (to keep
   the regression comparison honest) I re-created both and removed 9 broken empty-source leftovers by rule ID
   (2 on enrolment-sg, 7 on db-sg). Side effect: verify-lab-02 31/2 -> 32/1, verify-lab-04 38/1 -> 39/0 (first clean
   run since Lab 04), verify-lab-05 46/3 -> 47/2. The SG audit went from MED=11 to MED=7.
3. "no policies/ document contains an unexpanded variable": a FALSE POSITIVE. Lab 01's
   usms-self-manage-credentials.json uses ${aws:username}, an IAM policy variable that must survive (Step 7 says so).
   The check flagged any $. Changed it to [$][{]?[A-Z] - a $ followed by an UPPERCASE name, i.e. a shell variable
   such as ${USMS_ACCOUNT_ID} - and proved it still catches a real mistake.
Other verify fixes (Step 13): six queries missing SecurityGroups[0] and comparing IpProtocol with the NUMBER -1, and the
boundary-attachment check (nested quotes) - all tested.
