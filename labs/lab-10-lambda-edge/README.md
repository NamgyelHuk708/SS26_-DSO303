# AWS Practical Laboratory Report

**Tools used:** Floci 2.4.0 (local AWS emulator, Docker Compose, hybrid storage), AWS CLI v1, Node.js (local syntax checks), python3, Docker, git

**CloudFront path: A.** `cloudfront list-distributions` was supported, so a real distribution record was created and its Lambda associations read back from the API. Floci still runs **no** edge location – the request path is proven with `usms-edge-simulate.sh`.

---

## 1. Aim / Objective

The aim of this practical is to create `usms-student-data` – the bucket that `USMSStudentDataReadWrite` has named since Lab 01 – and put two Lambda@Edge functions in front of it: a **viewer-request** function that normalises the URI and refuses unauthenticated requests before the cache, and an **origin-response** function that adds security headers and a cache policy. Both are invoked with real CloudFront events, published as immutable versions, checked against the Lambda@Edge restrictions, associated with a CloudFront distribution and run end to end without CloudFront. Separately, a **regional** notifier is triggered by uploads to the bucket through an alias and a scoped resource policy. Everything is proven to survive a restart and recorded in `configs/lab-10.env`.

## 2. Introduction

Lambda@Edge runs code inside CloudFront, on the request path, at four trigger points: **viewer-request** (before the cache), **origin-request**, **origin-response** (after the origin replies, before caching) and **viewer-response**. Because code is replicated to hundreds of edge locations, the edge only accepts an immutable **published version**, forbids environment variables and VPC configuration, and caps viewer triggers at 128 MB and 5 seconds. Work that does not have to happen before the viewer is answered belongs in an ordinary **regional** Lambda function instead – here, reacting to a transcript upload.

### Key Features

- **Trigger points and their caps:** what each one may return (a request to continue, a response to stop)
- **The CloudFront event:** `Records[0].cf.{config, request, response}`; headers as lowercase keys holding arrays of `{key, value}`
- **Versions and aliases:** a version freezes code *and* configuration; an alias is a movable pointer – right for regional triggers, refused by the edge
- **Execution role vs resource policy:** what the code may do vs who may invoke it
- **Confused-deputy protection:** `--source-arn` and `--source-account` on the S3 permission
- **Replace-only APIs:** `update-assume-role-policy`, `put-bucket-notification-configuration`

## 3. Use Case

| Need | How it is met |
|---|---|
| A transcript is never served to a request without a session, and refusing costs no origin request | `usms-edge-viewer-request` returns 403 at viewer-request – the origin is never contacted |
| One cache entry per transcript, however the URL is typed | the same function lowercases the URI |
| Every transcript carries security headers the bucket cannot set | `usms-edge-origin-response` adds HSTS, nosniff, X-Frame-Options, Referrer-Policy (+ CSP in Exercise 1) and a cache policy, once per cache miss |
| The registrar is told when a transcript is uploaded | `usms-transcript-notifier:live`, triggered by `s3:ObjectCreated` under `transcripts/*.json` |
| Only our bucket may trigger the notifier | resource policy scoped by source ARN and account |
| Deploy and roll back the notifier without touching the trigger | alias `live` – one `update-alias` call |

## 4. System Architecture / Design

![Lab 10 architecture](LAB_10(image)/architecture.png)

The edge-location box shows the distribution with its two associations at their trigger points; the regional box shows the bucket, the notifier and logs; the IAM column shows who each function runs as and the two policies that now name a real bucket. In the simulator, Student → CloudFront → (cache miss) `usms-student-data` returns **200**.

## 5. Implementation Procedure

I checked the environment and probed the build (Lambda, S3, Logs, **CloudFront** and IAM all supported), then created and tagged the bucket. On `usms-lambda-exec-role` I added the `edgelambda.amazonaws.com` principal **as a separate statement**, so the `lambda.amazonaws.com` statement kept the confused-deputy conditions Lab 09 had added, and recorded the edge statement as an accepted finding. I packaged and created the viewer-request function, invoked it on the allow and deny paths, published version 1, then did the same for the origin-response function. I deliberately set environment variables on the edge function, showed the call succeeds, removed them and checked both functions statically. I created the CloudFront distribution with both version-qualified associations, ran the chain with `usms-edge-simulate.sh`, then created the notifier with an alias, rolled the alias forward and back, added a scoped resource policy and wired the bucket notification. I restarted Floci, re-read everything, wrote `configs/lab-10.env`, verified (51/51) and committed.

## 6. Results and Evidence

### 6.1 CLI Output

Environment and storage check

![Step 1](LAB_10(image)/1.png)

*Floci up; storage check exit code 0 with five `[ok]` lines (my version of the script reports `[ok]` lines rather than a PASS total)*

---

Every lab environment sourced

![Step 2](LAB_10(image)/2.png)

*9 env files sourced; `USMS_ROLE_LAMBDA` is an ARN in my lab-01.env, so I derived the role name*

---

Support probe

![Step 4](LAB_10(image)/4.png)

*Floci 2.4.0: Lambda, layers, S3, Logs, **CloudFront** and IAM all SUPPORTED – Path A*

---

The origin bucket

![Step 5](LAB_10(image)/5.png)

*`head-bucket: exit 0` for the first time in the course (Lab 09 got 404); tagged; the policy's ARNs now resolve*

---

The execution role before

![Step 6.1](LAB_10(image)/6.1.png)

*One statement: lambda.amazonaws.com with Lab 09's aws:SourceAccount / aws:SourceArn conditions*

---

The execution role after

![Step 6.2](LAB_10(image)/6.2.png)

*Two statements: lambda (conditions kept) and edgelambda; the edge statement recorded as an accepted finding*

---

The viewer-request handler

![Step 7](LAB_10(image)/7.png)

*Syntax OK; `${studentId.toLowerCase()}` intact on line 51 – the heredoc was quoted*

---

Creating the function

![Step 8](LAB_10(image)/8.png)

*One zip entry `index.mjs`; nodejs20.x, 128 MB, 5 s, Active, `$LATEST`*

---

The allow path

![Step 9.1](LAB_10(image)/9.1.png)

*URI lowercased, `x-usms-edge: viewer-request-allow;student=stu-00417` stamped*

---

The deny path

![Step 9.2](LAB_10(image)/9.2.png)

*A response object: status 403, `viewer-request-deny`, no `uri` key – the function decided, it did not fail*

---

Logs

![Step 10](LAB_10(image)/10.png)

*`LogResult` is the literal `None` (decoding it gave the garbage bytes); the log group exists with 0 bytes*

---

Version 1

![Step 11](LAB_10(image)/11.png)

*`…usms-edge-viewer-request:1`, version-qualified – the edge would accept it*

---

The origin-response function

![Step 12](LAB_10(image)/12.png)

*Created, Active; `${upstream[0].value}` intact*

---

Origin-response invoked and published

![Step 13](LAB_10(image)/13.png)

*Origin headers kept, 4 security headers + cache-control added; chain header `viewer-request-allow;student=stu-00417;origin-response`; version 1*

---

The mistake that succeeds

![Step 14.1](LAB_10(image)/14.1.png)

*Environment variables accepted on an edge function – CloudFront would reject them later, at association*

---

Edge eligibility

![Step 14.2](LAB_10(image)/14.2.png)

*Variables removed; both functions 6/6 ok, 0 failures*

---

The distribution configuration

![Step 15.1](LAB_10(image)/15.1.png)

*Both associations version-qualified (`:1`)*

---

The distribution

![Step 15.2](LAB_10(image)/15.2.png)

*EN6YGM2ZHZHDVP, en6ygm2zhzhdvp.cloudfront.net, Deployed; both associations read back from the API*

---

The edge chain – allow

![Step 16.1](LAB_10(image)/16.1.png)

*viewer-request → origin → origin-response; 200 with five added headers and the chain marker*

---

The edge chain – deny

![Step 16.2](LAB_10(image)/16.2.png)

*403 with a chain of one – the origin is never contacted*

---

The notifier source

![Step 17](LAB_10(image)/17.png)

*Compiles; two `os.environ.get` lines – legal for a regional function*

---

Notifier, version and alias

![Step 18.1](LAB_10(image)/18.1.png)

*python3.12, 256 MB, 30 s; `live` → 1, with two environment variables*

---

Rolling forward and back

![Step 18.2](LAB_10(image)/18.2.png)

*live → 2 → 1; versions $LATEST, 1, 2 throughout*

---

The resource policy

![Step 19](LAB_10(image)/19.png)

*s3.amazonaws.com may invoke `…:live` only from usms-student-data in account 000000000000*

---

Notification and first object

![Step 20](LAB_10(image)/20.png)

*usms-transcript-upload → `…notifier:live`; `transcripts/evidence/lab-08-scaling-evidence.json` – the first object in the bucket*

---

Did the notifier run?

![Step 21.1](LAB_10(image)/21.1.png)

*No log group; the first direct invoke timed out (Python image pull), the retry returned processed = 1, ExecutedVersion 1*

---

Delivery and the filter

![Step 21.2](LAB_10(image)/21.2.png)

*Floci's container log shows every USMS_NOTIFY line – only for direct invokes, none for the upload: S3 delivery is not implemented. Three identical lines from one timed-out command – the CLI retried*

---

Before the restart

![Step 22.1](LAB_10(image)/22.1.png)

*Functions, versions, alias, objects, notification and the distribution recorded*

---

After the restart

![Step 22.2](LAB_10(image)/22.2.png)

*IDENTICAL, and the chain still executes – the code survived, not only the names*

---

configs/lab-10.env

![Step 23](LAB_10(image)/23.png)

*25 exports, all populated; version ARNs read from the API; CloudFront yes / EN6YGM2ZHZHDVP*

---

The Lab 09 audit still holds

![Step 24](LAB_10(image)/24.2.png)

*usms-lambda-exec-role's edge statement ACCEPTED with its reason; HIGH=0*

---

The exercise screenshots are in [`Exercise.md`](Exercise.md).

### 6.2 AWS Console Verification

Floci has no console. Everything was verified by readback (`get-function-configuration`, `list-versions-by-function`, `get-alias`, `get-policy`, `get-bucket-notification-configuration`, `get-distribution`) and by `verify-lab-10.sh`, which passed **51 of 51**. On real AWS the same evidence would come from the Lambda console (Versions, Aliases, Configuration → Permissions, the Monitor tab), the CloudFront console (Behaviors → Function associations) and the S3 console (Properties → Event notifications).

## 7. Analysis and Discussion

**Observed:** functions created and invoked with real event shapes; requests modified and refused; responses modified; two functions composing; versions and an alias; the resource policy; the bucket, its tags and notification; a distribution record with version-qualified associations; persistence of all of it. **Recorded only:** the two-principal trust rule, the association rules (Floci does not validate them), the edge caps. **Not available:** edge execution, caching, latency and cost.

**Decisions and findings of my own:**

| Finding | What I did |
|---|---|
| The lab's Step 6 trust policy (one unconditioned statement) would have **silently removed the confused-deputy conditions Lab 09 Exercise 2 added** – the trust policy is replace-only | Two statements: lambda keeps its conditions, edgelambda separate; the edge statement is an accepted finding in the Lab 09 audit, which stays at HIGH=0 |
| `LogResult` is the literal string `None`; CloudWatch log groups are empty | Lambda stdout goes to **Floci's own container log** (`docker logs floci`), which became the evidence |
| S3 → Lambda notifications are stored but **not delivered** | Proven with a direct invoke over a real S3 event shape; the filter proven by reading its rules |
| A timed-out invoke ran **three times** (the CLI retried) | Event handlers must be idempotent – a "failed" call may have run |
| Floci published version 2 from unchanged code | Real AWS returns the existing version when nothing changed |
| `__pycache__` was not ignored, and `.gitignore` lacked a final newline | Added the rule; fixed the line that the missing newline had merged |
| My `USMS_ROLE_LAMBDA` is an ARN; Step 22's backtick literal is invalid JSON; Step 23 copied shell variables | Name derived with `${…##*/}`; `'usms-'` string literal; version ARNs read from the API |

**Floci vs real AWS.**

| | Real AWS | Floci 2.4.0 |
|---|---|---|
| Lambda functions, versions, aliases, invoke | full | works (each runtime in its own container; first invoke pulls an image) |
| `--log-type Tail`, CloudWatch Logs | always | `None`; log groups empty |
| S3 event notification to Lambda | delivered within seconds | stored, not delivered |
| CloudFront distribution | minutes to deploy, associations validated | stored and Deployed instantly, **not validated** |
| Lambda@Edge execution, caching, edge logs | yes | never – no emulator runs it |
| IAM / resource policies | evaluated | stored only |

## 8. Reflection

**What I learned.** The trigger point decides everything: viewer-request can refuse a request for the price of one edge execution, while origin-response runs once per cache miss and its output is cached for everyone. I learned that a published version freezes the whole configuration – Exercise 2 showed version 1 still running as the old role – and why the edge refuses aliases: a pointer that can move during replication would let different edge locations run different code. The execution role and the resource policy finally separated cleanly in my head: one is what the code may do, the other who may call it.

**Challenges.** The step I am most glad I checked was Step 6: following the lab literally would have undone my Lab 09 work without any error. Debugging the logs was the other one – the garbage bytes turned out to be the word "None" base64-decoded, and the real output was sitting in Floci's container log, which also revealed that one timed-out command had run my function three times.

**Real-world use.** I would put the cheap checks (URI normalisation, an HMAC token) in CloudFront Functions, keep Lambda@Edge for what needs more, use a response headers policy instead of code where possible, and always check edge configuration statically before an association – a successful `update-function-configuration` proves nothing about the edge.

## 9. Conclusion

`usms-student-data` now exists and the three policies that name it resolve to a real resource. Two edge functions were built, invoked on both paths, published, checked against the edge restrictions, associated with a CloudFront distribution and shown to compose; a regional notifier was deployed behind an alias with a scoped resource policy and a filtered notification. The work survived a restart, `configs/lab-10.env` records 25 values, and `verify-lab-10.sh` passes 51 of 51 – while the Lab 09 security posture was preserved, not overwritten.

## 10. Appendix

### Additional Files

- `labs/lab-10-lambda-edge/edge-viewer-request/index.mjs`, `edge-origin-response/index.mjs`, `transcript-notifier/notifier.py`
- `policies/trust-lambda-edge.json` (two statements), `policies/usms-edge-basic-policy.json` (Ex 2), `policies/usms-iam-accepted-findings.json`
- `templates/lab-10-*.json` (6), `configs/lab-10.env`
- `scripts/utilities/usms-edge-simulate.sh`, `verify-lab-10.sh`, `usms-edge-report.sh` (Ex 3); `scripts/cleanup/lab-10-cleanup.sh` (not run)
- `notes/lab-10-notes.md`, `notes/lab-10-edge-design.md` (Ex 4), `labs/lab-10-lambda-edge/Exercise.md`
- Simulator: `USMS Lab 10 - edge functions.json`

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