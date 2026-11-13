# Lab 10 notes

## Environment
- Floci 2.4.0. Support probe: Lambda, layers, S3, Logs, CloudFront and IAM all SUPPORTED -> Path A for Step 15.
- Storage check: exit code 0 with five [ok] lines (my script prints [ok] lines, not a PASS total).
- My lab-01.env stores USMS_ROLE_LAMBDA as a full ARN; I used ROLE_NAME=${USMS_ROLE_LAMBDA##*/}.
- EC2 instances are still stopped (Lab 09) - irrelevant here: Lab 10 uses only managed services.

## Step 5 - the bucket
head-bucket on usms-student-data: exit 0 for the first time (Lab 09 Step 6 got 404). The ARNs in
USMSStudentDataReadWrite (ec2-app, ecs-task, eks-node roles) and USMSStudentDataReadOnly now resolve. Floci still
enforces none of it - the change is in what the ARN refers to, not in enforcement.

## Step 6 - the edge principal, without undoing Lab 09
The lab's trust-lambda-edge.json is ONE statement with both principals and NO conditions. update-assume-role-policy
replaces the whole document, so applying it would have silently removed the aws:SourceAccount/aws:SourceArn conditions
Lab 09 Exercise 2 put on lambda.amazonaws.com. My version has two statements: lambda keeps its conditions;
edgelambda.amazonaws.com is a separate statement, recorded in policies/usms-iam-accepted-findings.json with a reason.
The Lab 09 audit still reports HIGH=0 (ACCEPTED=6, then 7 after Exercise 2).

## Steps 7-16 - the edge functions
- viewer-request: allow -> URI lowercased + x-usms-edge stamped; deny -> a 403 RESPONSE (no uri key), not an error.
- origin-response: keeps content-type/etag/server, adds 4 security headers + cache-control + the chain header.
- Step 10: --log-type Tail returned LogResult = None; base64-decoding the word "None" produced the garbage bytes.
  Log groups exist but are empty. Lambda stdout goes to Floci's own container log (docker logs floci).
- Step 14: env vars on an edge function were ACCEPTED by update-function-configuration (as on real AWS) - CloudFront
  rejects them later, at association. Version 1 was published before the mistake, so it was never affected.
- Step 15: create-distribution worked (EN6YGM2ZHZHDVP, Deployed instantly). Floci stores the associations WITHOUT
  validating them and runs no edge.
- Step 16: usms-edge-simulate.sh - allow: 3 stages, x-usms-edge-chain=viewer-request-allow;student=stu-00417;
  origin-response (composition); deny: 403, chain of one.

## Steps 17-21 - the regional notifier
- python3.12, 256 MB, 30 s, two environment variables (legal here), alias live -> 1 (rolled to 2 and back).
- Floci created version 2 from UNCHANGED code; real AWS returns the existing version when nothing changed.
- Resource policy: s3.amazonaws.com -> lambda:InvokeFunction on :live, AWS:SourceArn usms-student-data,
  AWS:SourceAccount 000000000000.
- S3 -> Lambda delivery is NOT implemented on Floci 2.4.0: the notification is stored, but no upload produced an
  invocation. The direct invoke with --qualifier live returned processed=1, ExecutedVersion 1.
- The first direct invoke timed out while Floci pulled the python3.12 image; the AWS CLI retried and the handler ran
  THREE times (three identical USMS_NOTIFY lines at 05:19:42). A "failed" call ran three times -> handlers must be
  idempotent.
- Filter: notes/ignore-me.json (wrong prefix) and transcripts/evidence/ignore-me.txt (wrong suffix) are excluded by the
  rules; with no delivery, this is proven by reading the filter.

## Steps 22-24
- Restart: IDENTICAL (functions, versions, alias, objects, notification, distribution), and the chain still executed.
- lab-10.env: 25 exports; the version ARNs and role ARN read from the API (the lab copied shell variables, empty in a
  new terminal). verify-lab-10.sh: PASS=51 FAIL=0.
- .gitignore: added __pycache__/; it had no final newline, so the first attempt merged it into ".idea/" - fixed.

## Review Questions

### Q1. "Move the whole enrolment API to Lambda@Edge - it will be faster for everyone"
Strongest argument 1: the enrolment API is a **write path that needs its data** - the database, the queue, the
transcripts bucket - all in one region. An edge function runs near the viewer but every call it makes to that data
crosses back to us-east-1, so the slow part (the round trip to the data) gets *longer*, not shorter, and each edge
location adds its own connection set-up. Strongest argument 2: the **edge restrictions** - no VPC access (the database
is in a private subnet), no environment variables, 5 s / 128 MB at viewer triggers, versions replicated over minutes,
logs scattered across regions - make it unsuitable for an application tier, and edge invocations cost more than
regional ones. They would be right for a **read-mostly, cacheable or computable-at-the-edge** piece: for example
refusing unauthenticated requests or redirecting by country before anything reaches the origin, or serving a response
that depends only on the request - exactly what usms-edge-viewer-request does.

### Q2. CloudFront Functions vs Lambda@Edge
CloudFront Functions: a lightweight JavaScript runtime (cloudfront-js), **viewer-request and viewer-response only**,
sub-millisecond, no network access and no body access, tiny memory, run at every edge location, priced at roughly a
sixth of Lambda@Edge per request. Lambda@Edge: Node.js or Python, **all four trigger points**, up to 5 s / 128 MB at
viewer triggers and 30 s / 10 GB at origin triggers, can make network calls and read the body, runs at regional edge
caches, costs more per request plus duration. Adding /index.html to a URI -> **CloudFront Function** (a string
rewrite on every request). Checking a JWT signature -> **CloudFront Function** if it is an HMAC signature
(cloudfront-js-2.0 has a crypto module), **Lambda@Edge viewer-request** for RS256/JWKS where a public key must be
fetched or more CPU time is needed. Fetching a per-user redirect from DynamoDB -> **Lambda@Edge**, because it needs a
network call, which CloudFront Functions cannot make (ideally at origin-request, so cached responses skip it).

### Q3. origin-response vs viewer-response
Both produced the same headers, but **origin-response runs only on a cache miss**, before the object is stored, so the
headers are cached with the object and served to every later viewer at no extra cost. **viewer-response runs on every
response, hits included** - with a high hit ratio that is orders of magnitude more invocations for identical output.
A requirement that forces viewer-response: a header that **differs per viewer or per request** and therefore must not
be cached - for example a per-request correlation ID, a header carrying the viewer's own session or country, or a
response that must vary with a value that is not in the cache key.

### Q4. Execution role vs resource policy - "redundant"?
They answer different questions about different calls. The **execution role** (usms-lambda-exec-role,
USMSLambdaBasic) is assumed by Lambda when the function runs; it governs **calls the function's code makes** - here
`head_object` on the bucket and writing logs. The **resource policy** on the function governs **who may call
lambda:InvokeFunction on it** - here S3, when an object is created. Delete the resource policy: S3 can no longer
invoke the function, so uploads silently stop triggering it - no error, no log, because the function never runs (on
real AWS put-bucket-notification-configuration would even refuse to validate the destination). Delete s3:GetObject
from the role: the function is still invoked, but its head_object call fails with AccessDenied (my handler records
readable=false/read_error rather than crashing). One is the door in, the other is what you may touch once inside.

### Q5. --source-arn and --source-account
Without them the statement says "the S3 service may invoke this function". An attacker in **another account** creates
their own bucket and configures its notification to target our function's ARN; S3 - acting on their behalf - is
allowed by our policy, so their uploads run our code (cost, log pollution, and our code acting on their input). That
is the **confused deputy**: a trusted service tricked into using its privilege for someone else. `--source-arn
arn:aws:s3:::usms-student-data` and `--source-account 000000000000` limit the permission to events coming from our
bucket in our account. Lab 09's equivalent is the **aws:SourceAccount / aws:SourceArn condition on the
usms-ecs-task-role trust policy** - and the same conditions kept on usms-lambda-exec-role in Step 6. Same idea: a
service principal is never trusted on its own; the request must also prove *on whose behalf* the service is acting.

### Q6. Environment variables accepted, configuration still invalid
`update-function-configuration` validates the **function** against **Lambda's** rules, and environment variables are
legal Lambda configuration - so it succeeds. The edge rules are checked by **CloudFront**, in a different API call
(`create-distribution` / `update-distribution`) about a different resource, when the function is associated - on real
AWS that is where InvalidLambdaFunctionAssociation appears, possibly minutes later and for someone else's change; on
Floci it never appears at all. So a command appearing to succeed is evidence only that *that* service accepted *that*
request - not that the result is what I meant. Edge configuration therefore has to be checked **statically, before
association**: Step 14's eligibility check and verify-lab-10.sh's "no environment variables" and "version-qualified
ARN" checks. It is the same lesson as Lab 09, where a revoke returned True and removed nothing, and as Step 21 here,
where a command that "timed out" had actually run three times.
