# Lab 11 Independent Exercises

---

## Exercise 1: A Second Build Project for the Results Service

I created `labs/lab-11-cicd/app-results/` with its own `VERSION` (`r1`), one HTML file with a `__RELEASE__` placeholder, and a `buildspec.yml` (pre_build checks VERSION; build substitutes the release and writes `build-metadata.json` with `"service": "results"`; post_build checks the placeholder is gone and the metadata parses). Its `dist/` is git-ignored.

The project `usms-results-build` was generated from Step 10's template by changing only the name, description, `source.location` (`source/usms-results-src.zip`), `artifacts.name`, the log group and the image (`python:3.12-slim`, because `standard:7.0` cannot be pulled – Step 12). It **reuses `usms-codebuild-role`**; source type **S3**, so it runs standalone.

![Exercise 1 - source tree and local build](LAB_11(image)/ex1.1.png)

![Exercise 1 - project and build](LAB_11(image)/ex1.2.png)

| Artifact | service | release | buildId |
|---|---|---|---|
| enrolment (`app/dist`) | enrolment | r5 | local |
| results (`app-results/dist`) | results | r1 | local |

![Exercise 1 - the two artifacts are distinguishable](LAB_11(image)/ex1.3.png)

The standalone build `usms-results-build:1` reported SUCCEEDED and wrote no object under `build/` – the same Floci 2.4.0 gap as the enrolment project (Lab README Section 7), now confirmed on a second project. `batch-get-builds` also returned `role: null`.

**Does `USMSCodeBuildBase` already permit this build?** Only partly: its S3 statement covers everything in `usms-pipeline-artifacts`, so reading `source/usms-results-src.zip` and writing `build/usms-results-build.zip` are allowed, but its log statement names only `/aws/codebuild/usms-enrolment-build`, so on real AWS this build's `CreateLogStream` in `/aws/codebuild/usms-results-build` would be denied – reusing the role needs a policy version 2 that adds the results log group (Floci, enforcing no IAM, would never show this).

---

## Exercise 2: A `finally` Block and a Build Report

`post_build` gained a `finally` block (a sibling of `commands`, same indentation) that writes `dist/build-summary.txt`: the release, the test result, the test exit status and a timestamp. Because `dist/` is the artifact's base directory, the summary ships in the artifact.

```yaml
  post_build:
    commands:
      - echo "--- post_build ---"
      - rm -f /tmp/usms-smoke-status
      - SMOKE=0; bash tests/smoke.sh || SMOKE=$?; echo "$SMOKE" > /tmp/usms-smoke-status; exit "$SMOKE"
      - ls -l "$ARTIFACT_DIR"
      - cat "$ARTIFACT_DIR/build-metadata.json"
    finally:
      - |
        STATUS=$(cat /tmp/usms-smoke-status 2>/dev/null || echo "not-run")
        RESULT=$([ "$STATUS" = "0" ] && echo passed || echo FAILED)
        ...  > "$ARTIFACT_DIR/build-summary.txt"
```

![Exercise 2 - the buildspec change](LAB_11(image)/ex2.1.png)

| Run | post_build commands | `build-summary.txt` | Phase |
|---|---|---|---|
| normal | exit 0 | `release=r5 tests=passed exit=0` | SUCCEEDED |
| health endpoint broken | **exit 1** | **`release=r5 tests=FAILED exit=1`** | **FAILED** |

The summary is produced when the tests fail, and the `finally` block does **not** rescue the phase.

**A bug my own test caught.** My first version was `bash tests/smoke.sh; echo $? > file; exit …`. Under errexit (`set -e` in my harness, and CodeBuild's fail-on-error behaviour) the shell stops at the failing test, so the status was never written – and `finally` then read a **stale `0` left by the previous run** and reported `tests=passed` for a failed build. A summary that says "passed" on a failure is worse than none. The fix captures the status with `|| SMOKE=$?` (allowed under errexit) and deletes the status file at the start of the phase.

![Exercise 2 - both runs, the bug and the fix](LAB_11(image)/ex2.2.png)

**How I tested it, and what I can claim.** The course's local runner reads only `commands` and ignores `finally`, and Floci 2.4.0 cannot execute a buildspec against the source (Lab README Section 7). I therefore tested the phase with a small harness that runs `post_build.commands` in one shell with `set -e` and then always runs `post_build.finally`, as CodeBuild documents. The claim is "the summary is produced on a failed test under CodeBuild's documented semantics", not "I observed it in CodeBuild".

---

## Exercise 3: Make the Configuration Check Robust

The `pre_build` container check no longer greps the file's text; it parses the JSON with the standard library and names both values:

```yaml
      - |
        python3 -c "import json,sys; c=json.load(open('config/service.json')).get('container'); sys.exit(0) if c == 'enrolment-api' else sys.exit('container mismatch: expected enrolment-api, found %s in config/service.json' % c)"
```

| Test | Result |
|---|---|
| `config/service.json` re-written with 4-space indentation | build **passes** (exit 0) – indifferent to formatting |
| container changed to `enrolment-api-v2` | **`container mismatch: expected enrolment-api, found enrolment-api-v2 in config/service.json`**, exit 1 |
| restored | no diff, passes |

![Exercise 3 - the parsed check](LAB_11(image)/ex3.1.png)

The trust policy now has two conditions: `aws:SourceAccount` and `ArnLike aws:SourceArn` naming **both** projects (`usms-enrolment-build` and, because Exercise 1 reuses the role, `usms-results-build`). The previous document is kept as the undo.

![Exercise 3 - the trust policy](LAB_11(image)/ex3.2.png)

**What `aws:SourceArn` closes that `aws:SourceAccount` alone does not:** `aws:SourceAccount` stops CodeBuild acting for another account, but anyone in this account who can create a project and pass this role could create their own project, name `usms-codebuild-role`, and run any commands with its permissions – read every artifact and plant a tampered build artifact for Lab 12 to deploy. With `aws:SourceArn` limited to the two project ARNs, CodeBuild assumes the role only on behalf of those projects. PassRole controls who may *name* the role; SourceArn controls which project the role will *work for*.

---

## Exercise 4: Trigger the Pipeline Without Polling

**Design.** A new version of `source/usms-enrolment-src.zip` → S3 emits `Object Created` to EventBridge → a rule matching that one key → target `codepipeline:StartPipelineExecution`, invoked with a role EventBridge assumes. `PollForSourceChanges` stays `"false"`.

| Document | Content |
|---|---|
| `templates/lab-11-eventbridge-rule.json` | `source aws.s3`, `detail-type Object Created`, `detail.bucket.name usms-pipeline-artifacts`, `detail.object.key source/usms-enrolment-src.zip` |
| `templates/lab-11-eventbridge-target.json` | the pipeline ARN, with `RoleArn usms-events-pipeline-role` |
| `policies/trust-events-pipeline.json` | `events.amazonaws.com`, `aws:SourceAccount`, `aws:SourceArn` = the one rule |
| `policies/usms-events-start-pipeline-policy.json` | `codepipeline:StartPipelineExecution` on one pipeline ARN |

![Exercise 4 - documents, rule and target](LAB_11(image)/ex4.1.png)

**The two routes to EventBridge are not equivalent.** The bucket's own EventBridge setting (`EventBridgeConfiguration`) emits `Object Created` for every object write, without extra cost. The other route, CloudTrail **data events**, emits `AWS API Call via CloudTrail` with `eventName: PutObject` and requires a trail with S3 data events enabled (charged per event). Matching one key works on both, with different patterns; I used the bucket setting (the notification configuration is replace-only, so I checked it was empty first).

**Why the target has its own role.** The caller is EventBridge, and all it needs is `StartPipelineExecution` on one pipeline. The pipeline role can read every artifact, start builds and pass the build role – none of which an event rule should hold.

**What ran on Floci 2.4.0:**

| Link | Result |
|---|---|
| bucket EventBridge configuration, rule, target, role | stored and read back |
| S3 → EventBridge delivery, rule matching one key | **observed** – the EventBridge invoker ran right after the upload |
| EventBridge → CodePipeline | **not available**: `unsupported target ARN type: arn:aws:codepipeline:…` |
| a new execution | before = 4, after = 4 |

![Exercise 4 - the upload test](LAB_11(image)/ex4.2.png)

---

## Exercise 5: Prepare the Deployment Contract for Lab 12

The `build` phase writes `dist/imagedefinitions.json`: a JSON **array** with one entry whose `name` is read from `config/service.json` (not hard-coded) and whose `imageUri` comes from `IMAGE_URI`, defaulting to the current placeholder `public.ecr.aws/nginx/nginx:stable-alpine`. The variable is **exported** so the `python3` process can read it from its environment.

| Build | `imagedefinitions.json` |
|---|---|
| default | `[{"name": "enrolment-api", "imageUri": "public.ecr.aws/nginx/nginx:stable-alpine"}]` |
| `IMAGE_URI=…/usms-enrolment:r5` | `[{"name": "enrolment-api", "imageUri": "000000000000.dkr.ecr.us-east-1.amazonaws.com/usms-enrolment:r5"}]` |

The file sits at the artifact root next to `index.html`. An eighth smoke-test assertion checks it is an array with exactly one entry naming `enrolment-api` and a non-empty `imageUri`; writing an object instead makes that assertion fail.

![Exercise 5 - the contract](LAB_11(image)/ex5.1.png)

![Exercise 5 - override and the eighth assertion](LAB_11(image)/ex5.2.png)

`outputs/lab-11-lab08b-readiness.txt` was generated by a re-runnable python3 sequence and is git-ignored. It records the pipeline (2 stages), the project (source CODEPIPELINE), **no pipeline BuildOutput key** (stated honestly: Floci does not produce artifacts), the local-runner evidence, the array, the container name's source, the `IMAGE_URI` override and the artifact file list.

![Exercise 5 - readiness file](LAB_11(image)/ex5.3.png)

---

## Summary

| Exercise | Result |
|---|---|
| 1 | `usms-results-build` (S3 source, same role); distinguishable artifacts; the role's log statement would need a v2 |
| 2 | `finally` writes `build-summary.txt` on failure without rescuing the phase; a stale-status bug found and fixed |
| 3 | JSON-parsed container check (formatting-proof, names both values); `aws:SourceArn` for two projects |
| 4 | event-driven design; S3 → EventBridge delivery observed; CodePipeline target unsupported on Floci |
| 5 | `imagedefinitions.json` array at the artifact root, name from config, `IMAGE_URI` override; 8th assertion; readiness file |