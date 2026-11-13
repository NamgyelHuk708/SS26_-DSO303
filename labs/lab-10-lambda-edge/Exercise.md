# Lab 10 Independent Exercises

---

## Exercise 1: Extend the Security Header Set

### What I did
I added `Content-Security-Policy: default-src 'self'` as **one new entry in the `SECURITY_HEADERS` object** – a data change, not a second block of code – checked it with `node --check`, rebuilt the archive, ran `update-function-code` on `$LATEST` and published **version 2**. Version 1 was not touched.

| Qualifier | Code size | Security headers | CSP |
|---|---|---|---|
| `$LATEST` | 1124 | **5** | `default-src 'self'` |
| `1` | 1092 | **4** | – |
| `2` | 1124 | **5** | `default-src 'self'` |

`templates/lab-10-distribution-config.json` now names `usms-edge-origin-response:2`. Because this build supports CloudFront (Path A), I also updated the **real** distribution: `get-distribution-config` → change the origin-response ARN to `:2` → `update-distribution --if-match <ETag>` (the ETag stops two edits overwriting each other). The distribution read back `origin-response → …:2`, and `verify-lab-10.sh` still passed 51/51.

![Exercise 1](LAB_10(image)/ex1.1.png)

A published version is immutable: version 1 still serves four headers, so rolling the edge back is just pointing the association at `:1` again. On real AWS that rollback would take minutes to replicate, and objects already cached would keep the headers they were cached with until their TTL expires or they are invalidated – Floci accepted the change instantly and has no cache.

---

## Exercise 2: A Dedicated Edge Execution Role

The edge functions never touch the bucket, yet they ran as `usms-lambda-exec-role`, which carries `s3:GetObject`.

| Item | Value |
|---|---|
| Policy | `USMSEdgeBasic` (`policies/usms-edge-basic-policy.json`): `logs:CreateLogGroup`, `logs:CreateLogStream`, `logs:PutLogEvents` only – **no S3** |
| Resources | `arn:aws:logs:us-east-1:000000000000:log-group:/aws/lambda/usms-edge-*` (and `…:*` for the streams) **and** `arn:aws:logs:*:000000000000:log-group:/aws/lambda/us-east-1.usms-edge-*` – at a real edge location a function logs to `/aws/lambda/us-east-1.<name>` in the region nearest the viewer, so the region is a wildcard but the name stays scoped |
| Role | `usms-edge-exec-role`, trust `policies/trust-lambda-edge.json` reused as-is |
| Untouched | `usms-lambda-exec-role` still carries only `USMSLambdaBasic` – the notifier still needs it |
| New versions | viewer **2**, origin **3** |

![Exercise 2 - role and policy](LAB_10(image)/ex2.1.png)

| Function | Version 1 runs as | `$LATEST` runs as |
|---|---|---|
| usms-edge-viewer-request | `usms-lambda-exec-role` | `usms-edge-exec-role` |
| usms-edge-origin-response | `usms-lambda-exec-role` | `usms-edge-exec-role` |

![Exercise 2 - role per version](LAB_10(image)/ex2.2.png)

**What happened to version 1's role? Nothing.** A published version freezes the **whole configuration**, not only the code – role, memory, timeout, runtime, environment. Changing the role changed `$LATEST` and every version published afterwards. So **rolling the edge back to `:1` would also roll back to the older, broader role.** A security fix in a role only takes effect once the versions that matter are republished and re-associated, and old versions should never be re-associated (or should be deleted) once nothing depends on them.

The new role also trusts `edgelambda.amazonaws.com` without a condition, so I recorded it in `policies/usms-iam-accepted-findings.json` with its reason (its only permission is log writes), keeping the Lab 09 audit at HIGH=0.

---

## Exercise 3: An Edge-Readiness Report

`scripts/utilities/usms-edge-report.sh` emits one JSON document listing every `usms-` function. One `list-functions` call returns runtime, memory, timeout, environment and VPC for every function; versions and aliases need one call each. Names come from the listing – there is no hard-coded list (the foreign `wine-mlops` function is excluded by the `usms-` prefix, not by name).

```json
[
  { "name": "usms-edge-origin-response", "runtime": "nodejs20.x", "memory": 128, "timeout": 5,
    "versions": 3, "aliases": 0, "env_vars": false, "edge_eligible": true,  "reasons": [] },
  { "name": "usms-edge-viewer-request",  "runtime": "nodejs20.x", "memory": 128, "timeout": 5,
    "versions": 2, "aliases": 0, "env_vars": false, "edge_eligible": true,  "reasons": [] },
  { "name": "usms-transcript-notifier",  "runtime": "python3.12", "memory": 256, "timeout": 30,
    "versions": 2, "aliases": 1, "env_vars": true,  "edge_eligible": false, "reasons": ["2 environment variable(s)"] }
]
```

| Constraint | How it is met |
|---|---|
| valid JSON on stdout only | built with `json.dumps` in python3 (string concatenation in bash breaks on quotes and empty lists); the count goes to stderr |
| any directory | `REPO_ROOT` from `${BASH_SOURCE[0]}`; identical output from `~` and from `labs/lab-10-lambda-edge/` |
| no `set -u` failure when `Environment` is absent | read in Python as `(f.get("Environment") or {}).get("Variables") or {}` – an absent key is an empty dict |
| no hard-coded list | names filtered from `list-functions` |

**The notifier, honestly.** Under the rules the exercise states, the notifier fails `edge_eligible` for **one** reason – its environment variables. Its 256 MB / 30 s are *within* the origin-trigger caps (10,240 MB / 30 s), because its name does not contain "viewer". It would fail a second, independent reason only if judged as a viewer function (both 256 MB > 128 MB and 30 s > 5 s). I added a `reasons` field so a `false` is never unexplained.

![Exercise 3](LAB_10(image)/ex3.png)

---

## Exercise 4: Design the Transcript Delivery Policy

The design document is `notes/lab-10-edge-design.md`. Summary of the decisions:

| Requirement | Decision |
|---|---|
| Valid session token, refused without an origin request | token check at **viewer-request** – a **CloudFront Function** if the token is HMAC-signed, **Lambda@Edge** if it must verify an RS256 JWT; URI normalisation as a CloudFront Function |
| Security headers | a CloudFront **response headers policy** (no code), or origin-response as built in this lab |
| Cache key | the normalised URI only – **not** the token, cookies or query string |
| Corrections within five minutes, no re-fetching unchanged transcripts | long edge TTL + **targeted invalidation** triggered by the S3 upload (regional Lambda), with `max-age=300` for browsers; alternative: short TTL + ETag revalidation (`304`) |
| Refusals by faculty | **CloudFront standard logs + Athena**, not edge function logs (they land in the region nearest each viewer) |
| One edge location cannot reach the origin | not an edge-function job – a **CloudFront origin group with failover** to a replica bucket |
| Measure first | cache hit ratio and corrections per day – frequent corrections would favour revalidation over invalidation |

![Exercise 4](LAB_10(image)/ex4.png)

---

## Exercise 5: Hand the S3 Lab a Bucket It Can Start From

**Part 1 – validate the Lab 09 draft against the real bucket.** `outputs/lab-09-bucket-policy-draft.json` (from Lab 09 Exercise 5) was checked statement by statement: every `Resource` must be the existing bucket (with and without `/*`) and every principal ARN (in `Principal` and in the `NotPrincipal` list, the account root excepted) must be an existing role. Mismatches would be reported, not fixed. The draft was **not applied**: `get-bucket-policy` fails with `NoSuchBucketPolicy` – correct, applying it is the S3 configuration lab's step.

![Exercise 5 - validation](LAB_10(image)/ex5.1.png)

**Part 2 – upload the allow trace.** `outputs/lab-10-edge-trace.json` (chain `viewer-request -> origin -> origin-response`) was uploaded to `transcripts/evidence/lab-10-edge-trace.json`. Because this build stores the notification but does not deliver events (Step 21), I proved the notifier handles that exact object by invoking `usms-transcript-notifier --qualifier live` with an S3 event built for that key: `processed: 1`, and the `USMS_NOTIFY` line appears in Floci's container log.

![Exercise 5 - upload and notifier](LAB_10(image)/ex5.2.png)

**Part 3 – `outputs/lab-10-s3-readiness.txt`**, generated by a re-runnable python3 sequence (not by hand) and git-ignored: bucket name and ARN; the objects under `transcripts/`; the notification id, target (`…notifier:live`) and filter (`s3:ObjectCreated:*`, `transcripts/`, `.json`); the published versions of the three functions; CloudFront supported; the Part 1 result; no bucket policy applied; and a warning that `put-bucket-notification-configuration` is replace-only, so the S3 lab must get, merge and put.

![Exercise 5 - readiness file](LAB_10(image)/ex5.3.png)

---

## Summary

| Exercise | Result |
|---|---|
| 1 | CSP added as one data line; version 2 published; v1 still 4 headers; config file and the real distribution point at `:2`; verify 51/51 |
| 2 | `usms-edge-exec-role` + `USMSEdgeBasic` (logs only, edge-aware log ARNs); v1 keeps the old role – a version freezes configuration |
| 3 | `usms-edge-report.sh`: valid JSON, any directory, no hard-coded list; notifier false for one stated reason, explained in `reasons` |
| 4 | `notes/lab-10-edge-design.md`: CloudFront Function vs Lambda@Edge per piece, cache key, invalidation vs revalidation, logs + Athena, origin failover |
| 5 | Lab 09 draft validated against the real bucket and not applied; trace uploaded and handled; reproducible readiness file |