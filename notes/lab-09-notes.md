## Exercises - short record
- Ex 1: usms-app-sg egress written (S3 prefix list 443, 443 out, 80 -> usms-alb-sg, 5432 -> usms-db-sg, DNS udp+tcp
  53 -> 10.0.0.2/32). Unquoted heredoc (four IDs expanded now). Authorised first, default revoked by rule ID.
  verify-lab-09 still 50/0. Bastion egress should be tcp/22 -> usms-app-sg only.
- Ex 2: usms-breakglass-role (MFA AND ExternalId in one Condition block, 3600 s, USMSPermissionsBoundary,
  RegisterScalableTarget + DescribeScalableTargets). ecs-exec and lambda trusts conditioned. Five findings accepted
  in policies/usms-iam-accepted-findings.json, each with a reason; usms-iam-audit.sh prints ACCEPTED and still exits 1
  for unaccepted HIGH. After re-inventory: HIGH=0 MED=40 ACCEPTED=5 roles=13, exit 0.
  (The audit reads the Step 4 inventory - it must be re-run after any IAM change.)
- Ex 3: usms-exposure-report.sh - 1 EXPOSED (usms-web-01), 5 ISOLATED; identical from two directories. The matrix
  (instance PublicIpAddress) and the report (interface Association.PublicIp) disagree on the Lab 03 leftovers.
- Ex 4: USMSReportingReadOnly is the third policy naming the bucket, attached to nothing. usms-admin-01 reaches
  transcripts only indirectly (USMSAssumeAppRoles). get-account-authorization-details and Access Analyzer both
  answered on 2.4.0; the account-wide scan agreed with the per-policy lookups.
- Ex 5: bucket-policy draft computed from the three policies; 17 exports in lab-09.env.

## Review Questions

### Q1. Why "nothing broke" is a strong result
Step 18 re-ran five verification scripts written in earlier labs - before anyone knew what Lab 09 would change - and
their summary lines were identical to the Step 2 baseline. That is strong because those scripts encode what the
earlier labs promised (the service is ACTIVE, the load balancer routes, the subnets are private), and none of them was
written to make this lab pass. A plausible change that would have broken one: removing tcp/22 from 10.0.0.0/16 on
usms-app-sg, if verify-lab-02 had asserted that exact rule; or writing usms-alb-sg's egress to a CIDR that missed the
tasks. If that happened I would read the failing check, decide whether its assertion is still the right promise, and
either fix my change or update the check with a written reason (the documented-change route Lab 05 Step 13 describes) -
never silently delete it. In my run the opposite also happened: restoring two lost rules AFTER Step 18 improved
verify-lab-02/04/05, which I recorded separately so it could not mask a regression.

### Q2. Attaching the boundary as an ordinary policy
If a colleague runs attach-role-policy with USMSPermissionsBoundary on usms-deploy-role, the boundary policy becomes a
GRANT. In one direction the role gains everything the boundary's Allow lists (ecs:*, elasticloadbalancing:*, logs:*,
cloudwatch:*, application-autoscaling:*, s3:PutObject on "*", ...) - far more than USMSDeployBase, which deploys three
ECS calls. In the other direction nothing is capped any more if the real boundary is ever removed: the ceiling and the
grant are now the same document. It becomes dangerous the moment the role keeps its boundary slot empty or someone edits
the boundary to be broader - then "ceiling" and "permissions" grow together. Section 8's check "the boundary is attached
to NOTHING as an ordinary policy" (list-entities-for-policy = 0) catches it.

### Q3. Every ingress rule correct, still a breach
An attacker exploits a code-injection bug in the enrolment API through the legitimate load-balancer path - every ingress
rule did exactly its job. The task role can read every transcript (and, with my Lab 01 policy, write and delete them).
Before Lab 09 the task could send the data anywhere on any port (DNS tunnelling, a reverse shell on 4444, SMTP). Step 13
narrowed that to tcp/443 only - but an HTTPS POST to the attacker's server still works, so it narrows the channel
without closing it. What would prevent it entirely: egress filtering by HOSTNAME (AWS Network Firewall with a domain
allow-list, or an egress proxy) together with VPC endpoint policies and least-privilege data access (the read-only
role). This course cannot build it because Floci has no Network Firewall, no proxy service and carries no real traffic.

### Q4. sts:AssumeRole from an attacker's own machine
usms-ecs-task-role and usms-transcripts-reader-role trust only the SERVICE principal ecs-tasks.amazonaws.com, with
aws:SourceAccount and aws:SourceArn conditions: an attacker's own IAM user cannot assume them at all (the principal does
not match), and the conditions also stop the attacker's ECS account from making the service assume them on its behalf.
They differ only in what a successful compromise of a TASK would give (read/write vs read-only). usms-deploy-role trusts
the named user usms-admin-01: an attacker who has that user's credentials CAN assume it from anywhere - but what they get
is capped by USMSPermissionsBoundary and USMSDeployBase (no IAM changes, PassRole to three roles and only to ECS). The
difference is the principal type: a service principal can only be used through the service; a user principal can be
used by whoever holds the user's keys - which is why the real hardening for the deploy role is MFA.

### Q5. Five controls vs one
Five controls on usms-db-01 are not "five times better" because they do not fail independently in every scenario: the
public-IP, auto-assign and route-table controls all defend against the same thing (reaching it from the internet), and a
single mistaken change - moving the instance to a public subnet - defeats two of them at once. Their value is that each
one fails in a DIFFERENT way, so one mistake rarely removes them all. usms-enrolment-sg looked like a single point of
control in the matrix, but the matrix models only security groups: the tasks also sit in private subnets with no public
address and no internet-gateway route, behind the custom NACL. So they are not genuinely less protected from the
internet - they are less protected from a mistake in that ONE rule from inside the VPC, which is what the matrix shows.

### Q6. The two extra rotation steps
Step 2 (move every consumer to the new key and prove it works) protects against an OUTAGE: if the profile were not
switched, deleting the old key would break every lab using --profile usms-dev (InvalidClientTokenId). Step 3 (deactivate
before delete) protects against an UNKNOWN consumer: if a forgotten script still used the old key, it fails while the
key can still be reactivated with one call, instead of after deletion, when nothing can bring it back. A long-lived key is
a compromise because it is a password that never expires, can be copied anywhere and works from anywhere. A real system
would give humans temporary credentials through IAM Identity Center / federation (with MFA), and workloads would use
roles (instance profiles, task roles, IRSA) - so no long-lived key would exist.

### Q7. Review vs testing
Reading is an adequate substitute for testing claims about what CANNOT happen, which is most of security: no test can
try every action, principal and condition, but reading a document shows exactly what it allows. A defect reading catches
that testing would not: USMSStudentDataReadWrite grants s3:DeleteObject that no workload uses - every test of the
enrolment flow passes, but the excess verb is visible only in the document. A defect testing catches that reading would
not: in Step 13 the revoke returned True and a lookup returned 0, and only reading the rule back showed it was still there
- the documents (and the lab's checks) "looked" right while the actual state was wrong; equally, a condition key the
service never sends looks correct on paper and only fails when tried. For student transcripts I would want reading
first - it gives a complete answer about who CAN access them - followed by tests of the important paths, because a
review that is never checked against the real state can be confidently wrong.