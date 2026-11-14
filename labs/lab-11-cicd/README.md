# AWS Practical Laboratory Report

**Tools used:** Floci 2.4.0 (local AWS emulator, Docker Compose, hybrid storage), AWS CLI v1, python3 (PyYAML), zip, Docker, git

**CI/CD support path: A.** CodeBuild, CodePipeline, ECR and CodeDeploy all answered the probe. The **control plane** (projects, pipelines, executions, states, phase contexts) was observed; **build execution** was not – Section 7 explains exactly why, and the build evidence comes from the local buildspec runner.

---

## 1. Aim / Objective

The aim of this practical is to build the first two stages of a CI/CD pipeline for the USMS enrolment service: a versioned S3 artifact store whose versioning is proven by behaviour, an application source tree with a `buildspec.yml`, scoped CodeBuild and CodePipeline service roles (including a conditioned `iam:PassRole`), a CodeBuild project run standalone and by a local runner, and a two-stage pipeline (S3 Source → CodeBuild Build). The pipeline is exercised end to end with a changing release number, and a deliberate failure is diagnosed from stage to phase to command.

## 2. Introduction

A pipeline does not build: it moves zip files through an S3 artifact store and asks other services to act on them. CodePipeline calls `codebuild:StartBuild`; CodeBuild runs the phases of a `buildspec.yml` that lives **inside the source**, so changing the build is a reviewed, versioned source change. Two roles keep two blast radii apart: the pipeline may start one build and pass one role, and the build may write its logs and one bucket.

### Key Features

- **Versioned S3 source:** every upload is a new version; an execution can record exactly which bytes it built
- **buildspec 0.2:** `install → pre_build → build → post_build`, `artifacts.base-directory`, `finally`
- **Separate identities:** `usms-codepipeline-role` vs `usms-codebuild-role`
- **`iam:PassRole` with `iam:PassedToService`:** naming which role a service may be given, and to which service
- **Confused-deputy conditions:** `aws:SourceAccount` (and in Exercise 3 `aws:SourceArn`) on both trust policies
- **Local runner:** the same buildspec, phase by phase, on my laptop – and an honest distinction between "the build passed" and "the build passed locally"

## 3. Use Case

| Need | How it is met |
|---|---|
| Every release is traceable to the source it was built from | a versioned source object; `build-metadata.json` records release, build ID and source version |
| A misconfigured container name never reaches a deployment | `pre_build` validates `config/service.json` (parsed JSON since Exercise 3) and fails in seconds |
| A compromised build cannot touch student records | `USMSCodeBuildBase`: only its log group and the artifact bucket, plus an explicit Deny on `usms-student-data` |
| The pipeline cannot be used to escalate | it may start one project and pass one role, and only to CodeBuild |
| Lab 12 can deploy without guessing | `imagedefinitions.json` at the artifact root, container name read from the config (Exercise 5) |

## 4. System Architecture / Design

![Lab 11 architecture](LAB_11(image)/architecture.png)

A new source version (1) is the only input. The pipeline's Source stage reads that version and the Build stage starts CodeBuild (4), which writes the artifact back to the same bucket (5). Exercise 4 adds the event-driven trigger (2–3). The roles on the right are the two blast radii plus the event role; the box below the pipeline is Lab 12's Deploy stage and the `imagedefinitions.json` contract. In the simulator the chain Developer → S3 → EventBridge → CodePipeline → CodeBuild → S3 returns 200.

## 5. Implementation Procedure

I probed the build (Path A), created the artifact bucket with versioning, tags and a public-access block, and proved versioning by writing two versions to one key. I wrote the source tree and buildspec (adding a port-80 check of my own), created the CodeBuild role and project, packed the source with the buildspec at the zip root, and ran a standalone build. The first build FAULTed because `aws/codebuild/standard:7.0` cannot be pulled (404); I switched to the course's alternative `python:3.12-slim`. The next build reported SUCCEEDED but produced nothing, which I diagnosed (Section 7). I ran the buildspec locally with the runner, created the pipeline role, definition and pipeline, converted the project to a CODEPIPELINE source, rolled the release through r4 and r5, broke the container name on purpose and diagnosed it, recorded `configs/lab-11.env`, verified and committed.

## 6. Results and Evidence

### 6.1 CLI Output

Environment and earlier labs

![Step 1](LAB_11(image)/1.png)

*Floci up; storage check exit 0; lab-04 39/0, lab-05 47/2, lab-10 51/0*

---

Every lab environment sourced

![Step 2](LAB_11(image)/2.png)

*10 env files; container `enrolment-api`, target group and exec role present*

---

Support probe

![Step 3](LAB_11(image)/3.png)

*PATH A – CodeBuild and CodePipeline present; ECR and CodeDeploy also answer*

---

The artifact bucket

![Step 5](LAB_11(image)/5.png)

*Versioning Enabled, three tags, public access blocked (4 × True)*

---

Versioning proved by behaviour

![Step 6](LAB_11(image)/6.png)

*Two versions at one key (Latest True, size 7; False, size 6), then cleaned to 0*

---

The source tree

![Step 7](LAB_11(image)/7.png)

*VERSION r3, valid config naming enrolment-api on port 80, two placeholders*

---

The buildspec and my port check

![Step 8](LAB_11(image)/8.png)

*Parses with four phases; pre_build gains a `- |` port check (six commands)*

---

The CodeBuild role

![Step 9](LAB_11(image)/9.png)

*Trusts codebuild.amazonaws.com with aws:SourceAccount; one policy, USMSCodeBuildBase*

---

The CodeBuild project

![Step 10](LAB_11(image)/10.png)

*0 unexpanded `$`; source S3, 15-minute timeout*

---

The source archive

![Step 11](LAB_11(image)/11.png)

*buildspec.yml and VERSION at the zip root, no `app/`, no `dist/`; git-ignored*

---

The first build: FAULT

![Step 12.1](LAB_11(image)/12.1.png)

*`pull access denied for aws/codebuild/standard` (404) – the Known Issue, confirmed on Floci 2.4.0*

---

The second build on python:3.12-slim

![Step 12.2](LAB_11(image)/12.2.png)

*Image switched (the course's alternative), SUCCEEDED on the first poll*

---

Eleven phases, all 0 seconds

![Step 13](LAB_11(image)/13.1.png)

*Every phase SUCCEEDED in 0 s; no log text, no artifact under build/ – the start of the investigation*

---

The local runner

![Step 14.1](LAB_11(image)/14.1.png)

*Four phases, 7/7 smoke tests, exit 0, `release: r3`, `buildId: local`; dist/ git-ignored*

---

The port check, fixed and proved

![Step 14.2](LAB_11(image)/14.2.png)

*With port 8080 the build stops in pre_build with my message, exit 1 – after fixing a prefix-match bug*

---

The pipeline role

![Step 15](LAB_11(image)/15.png)

*USMSCodePipelineBase v1: artifact store, StartBuild on one project, PassRole on one role to CodeBuild only*

---

The pipeline

![Steps 16 and 17](LAB_11(image)/16&17.png)

*Valid template, two stages; no automatic first execution on Floci*

---

Hand the project to the pipeline

![Step 18](LAB_11(image)/18.png)

*Source and artifacts CODEPIPELINE; a plain start-build was still ACCEPTED (real AWS refuses it)*

---

The pipeline run

![Step 19.1](LAB_11(image)/19.1.png)

*Execution Succeeded, but no SourceOutput/BuildOutput objects; the build container lived 0.21 s*

---

The experiment

![Step 19.2](LAB_11(image)/19.2.png)

*The same build with the buildspec CONTENT inline: FAILED in PRE_BUILD and POST_BUILD*

---

The diagnosis

![Step 19.3](LAB_11(image)/19.3.png)

*Phase contexts: "VERSION file is missing", "tests/smoke.sh: No such file" – commands ran, the source was never delivered*

---

Release r4

![Step 19.4](LAB_11(image)/19.4.png)

*The same buildspec, local: `release: r4`, files at the artifact root*

---

Release r5 and the counts

![Step 19.5](LAB_11(image)/19.5.png)

*3 source versions, 2 Succeeded executions, 0 BuildOutput objects; local build `release=r5`*

---

A broken source, a green pipeline

![Step 20.1](LAB_11(image)/20.1.png)

*Container renamed: Source Succeeded, Build Succeeded, "Action completed."*

---

The diagnosis that worked

![Step 20.2](LAB_11(image)/20.2.png)

*Build 8 SUCCEEDED with no failed phase; the local runner: pre_build → "names the wrong container" → exit 1*

---

Fixed and pushed

![Step 20.3](LAB_11(image)/20.3.png)

*Local build passes again, then uploaded and executed; 5 source versions*

---

configs/lab-11.env

![Step 21](LAB_11(image)/21.png)

*26 exports, all populated; versioning Enabled, source CODEPIPELINE, image python:3.12-slim, stages 2, release r5, path A*

---

Verification

![Section 8](LAB_11(image)/22.png)

*PASS=46 FAIL=0 – configuration and existence, which is exactly why Section 7 matters*

---

The exercise screenshots are in [`Exercise.md`](Exercise.md).

### 6.2 AWS Console Verification

Floci has no console. Everything was verified by readback (`batch-get-projects`, `batch-get-builds` including phase `contexts`, `get-pipeline-state`, `list-pipeline-executions`, `list-object-versions`) and by Floci's own container log. On real AWS the same evidence would be the CodeBuild build history (phase details and the CloudWatch log), the CodePipeline execution history with its artifact links, and the S3 console's version list.

## 7. Analysis and Discussion

**The central finding: a green status was never evidence.** On Floci 2.4.0 every CodeBuild build after the image switch, and every pipeline execution, reported SUCCEEDED – yet no artifact was ever written and no log line from my buildspec appeared. I traced it in four steps:

| Evidence | What it showed |
|---|---|
| all 11 phases at 0 s, empty log stream, no object under `build/` | nothing visible had been built |
| Floci log: the `python:3.12-slim` container started and stopped after **0.14 s** | too short to start Python, let alone run four phases |
| the same build with `--buildspec-override "$(cat buildspec.yml)"` | now **FAILED** in PRE_BUILD and POST_BUILD – the commands ran |
| the phase `contexts` | `VERSION file is missing`; `tests/smoke.sh: No such file or directory` |

So Floci 2.4.0's CodeBuild (1) reads `source.buildspec: buildspec.yml` as an **inline** buildspec – a YAML document with no phases – instead of a path inside the source, and (2) does **not** deliver the S3 source into the build container, although `DOWNLOAD_SOURCE` reports success. The deliberate failure in Step 20 made the consequence concrete: a broken container name produced a **green pipeline**; only the local runner caught it.

**Other findings.**

| Finding | Meaning |
|---|---|
| `aws/codebuild/standard:7.0` → 404 pull access denied | the Known Issue still holds on 2.4.0; FAULT means CodeBuild could not run at all |
| no automatic execution on `create-pipeline` | real AWS starts one immediately |
| `start-build` on a CODEPIPELINE project accepted | real AWS refuses it – Step 18's cost was recorded, not observed |
| `batch-get-builds` returns `role: null` | there is no evidence of which identity a build ran as |
| `update-project --environment` replaced the whole block | the template's two environment variables were dropped – another replace-only API |
| my port check `"port": 80` matched `8080` | a prefix match; caught by the deliberate-failure test, fixed with `80([^0-9]|$)` |

**Observed vs recorded vs not available.**

| Observed | Recorded, not enforced/observed | Not available |
|---|---|---|
| versioning by two versions at one key; the zip layout; the buildspec's phases, smoke tests passing and failing (locally); a PRE_BUILD failure (locally and via contexts); the image 404; pipeline and project documents round-tripping; S3 → EventBridge delivery (Ex 4) | the build role's scope and Deny; the conditioned PassRole; the single project ARN; the CODEPIPELINE start-build refusal; artifacts in BuildOutput | a CodeBuild-produced artifact; CloudWatch build logs; an EventBridge → CodePipeline target; IAM enforcement; build cost and quotas |

## 8. Reflection

**What I learned.** The pipeline is mostly plumbing between zips in S3; the important design choices are where the buildspec lives (in the source), how the two roles are scoped, and what each execution records about the bytes it built. I also learned to ask of every success: *what would I see if this had done nothing?* Here, the answer was "exactly this".

**Challenges.** The hardest and most useful part was refusing to accept a SUCCEEDED build with no artifact. Tracing it from 0-second phases to a 0.14-second container to an inline-buildspec experiment, and finally to the build's own error message, took longer than the rest of the lab – and it turned a list of green ticks into a precise statement of what the emulator does and does not do. Twice my own deliberate-failure tests caught bugs in what I had written (the port prefix match, and in Exercise 2 a `finally` block reporting a stale "passed").

**Real-world use.** I would keep the buildspec in the repository, validate configuration in `pre_build`, run the same buildspec locally before every push, and treat an artifact's contents – not a status – as the evidence that a pipeline built what I think it built.

## 9. Conclusion

The artifact store, source tree, buildspec, two scoped roles, the CodeBuild project and the two-stage pipeline exist and pass verification (46/46), and `configs/lab-11.env` records 26 values for Lab 12. On this emulator the build execution itself could not be demonstrated: I proved why, and the same buildspec ran correctly through the local runner for r3, r4 and r5, failing exactly where it should when the configuration was broken.

## 10. Appendix

### Additional Files

- `labs/lab-11-cicd/app/` (VERSION, buildspec.yml, src/, config/service.json, tests/smoke.sh), `labs/lab-11-cicd/app-results/` (Ex 1)
- `policies/trust-codebuild.json`, `trust-codepipeline.json`, `usms-codebuild-policy.json`, `usms-codepipeline-policy.json`, `trust-events-pipeline.json`, `usms-events-start-pipeline-policy.json`
- `templates/lab-11-codebuild-project.json`, `lab-11-pipeline.json`, `lab-11-results-project.json`, `lab-11-eventbridge-rule.json`, `lab-11-eventbridge-target.json`
- `scripts/utilities/cicd-support-probe.sh`, `usms-pack-source.sh`, `usms-buildspec-run.sh`, `verify-lab-11.sh`; `scripts/cleanup/lab-11-cleanup.sh` (not run)
- `configs/lab-11.env`, `notes/lab-11-notes.md`, `labs/lab-11-cicd/Exercise.md`
- Simulator: `USMS Lab 11 - CI-CD pipeline.json`

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