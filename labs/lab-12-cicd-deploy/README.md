# AWS Practical Laboratory Report

**Tools used:** Floci 2.4.0 (local AWS emulator, Docker Compose, hybrid storage), Docker Desktop for Linux, AWS CLI v1, python3 (PyYAML), git

**Deployment path: A.** Docker, ECR and ECS all worked, and on this build they did real work: images were pushed to and pulled from a real registry, and ECS started containers from them. The pipeline's **ECS deploy provider is not available** on Floci 2.4.0, so the deploy action's mechanism was replayed by hand and is labelled as such throughout.

---

## 1. Aim / Objective

The aim of this practical is to take the enrolment service from source to a running container: create a private ECR repository, build and push an image (and explain tag versus digest), derive a new task definition revision that names it, deploy it to `usms-enrolment-svc`, version the two pipeline IAM policies, add an ECS Deploy stage to the Lab 11 pipeline with a get-modify-put, run a release end to end, roll a bad release back by hand, and specify a CodeDeploy blue/green deployment without performing one.

## 2. Introduction

A container release is a chain of names: a source version, a build, an image tag, an image digest, a task definition revision, and the revision a service runs. The ECS deploy action changes exactly one field in that chain – the image of one named container – by reading the service's current revision, swapping the image named in `imagedefinitions.json`, registering a new revision and updating the service. Everything else in the task definition travels unchanged, which is why it is derived, never rewritten.

### Key Features

- **Tag vs digest:** a tag is a movable name; the digest is the content's identity
- **Describe → strip → register:** deriving a revision so nothing (roles, cpu, memory, health check) is lost
- **Policy versions:** `create-policy-version --set-as-default`, and why the default is a separate decision
- **Replace-only APIs:** `update-pipeline` replaces the whole document – get, modify, put
- **Rollback by naming a revision:** a task definition family is an append-only log
- **Blue/green:** two target groups, a test listener, `appspec.yaml` and a deployment group – and the immutable deployment controller

## 3. Use Case

| Need | How it is met |
|---|---|
| The service runs USMS's own code, not a placeholder | image `usms-enrolment:r6`/`r7` built from `dist/`, pushed to ECR, pulled by ECS |
| A release can be traced to its source | execution `cf458f66` records source version `448a75df` (`VERSION r7`); `build-metadata.json` inside the container names the release |
| The build can push but cannot touch anything else | `USMSCodeBuildBase` v2: one repository; `GetAuthorizationToken` alone on `*` |
| The pipeline can deploy one service and nothing else | `USMSCodePipelineBase` v2/v3: one service ARN, family-scoped registration (v3), PassRole only to `ecs-tasks.amazonaws.com` |
| A bad release can be undone quickly | rollback by pointing the service at the previous revision (`:5`) |

## 4. System Architecture / Design

![Lab 12 architecture](LAB_12(image)/architecture.png)

The left column is delivery: my laptop builds and pushes the image (Floci's CodeBuild cannot – Lab 11), the versioned source bucket, the three-stage pipeline and the build project, the registry, the `imagedefinitions.json` contract and the rollback drill. The VPC on the right is runtime: Students → IGW → ALB (`:80` blue, `:8080` green from Exercise 3) → the Fargate service on `usms-enrolment:5`. In the simulator that path returns 200.

## 5. Implementation Procedure

I probed the build (Path A; CodeDeploy answered too), published an ECR port range (5100 was taken on my laptop, so host 5200–5204 → container 5100–5104 – and Floci actually serves the registry on 4566), created the repository and logged Docker in. I wrote the Dockerfile, built and pushed `r6`, proved it by digest, derived revision 4 from the revision the service ran (not the family's latest), deployed it and read the release from inside the tasks. I created both policy v2s, enabled `privilegedMode` (keeping `python:3.12-slim`), merged Lab 12's image build into my Lab 11 buildspec instead of replacing it, and added the Deploy stage with a guarded get-modify-put. The pipeline's Deploy stage failed (`Provider ECS is not available`), so I replayed the action by hand to deploy `r7` as revision 5. I ran the rollback drill with an unpushed `r8`, rolled back, deregistered revision 6, validated the blue/green documents, wrote `configs/lab-12.env`, verified and committed.

## 6. Results and Evidence

### 6.1 CLI Output

Environment and Lab 11's handover

![Step 1](LAB_12(image)/1.png)

*Floci up; lab-04 39/0, lab-05 47/2, lab-11 46/0; Docker reachable; the Lab 11 readiness file*

---

Environment and probe

![Steps 2 and 3](LAB_12(image)/2&3.png)

*11 env files, container enrolment-api; the service on usms-enrolment:2; PATH A, probe repositoryUri on …localhost:4566, CodeDeploy answers*

---

The port range

![Step 4](LAB_12(image)/4.png)

*5100 already in use on my laptop – Floci failed to start; remapped to host 5200–5204; the service survived the recreate*

---

Repository and login

![Steps 5 and 6](LAB_12(image)/5&6.png)

*MUTABLE, scanOnPush; `GET /v2/` on 4566 → 200, on 5200 → 000: the registry is on 4566; Login Succeeded with no daemon.json change*

---

The Dockerfile

![Step 7](LAB_12(image)/7.png)

*FROM nginx:1.27-alpine, COPY dist/ – the built output, never the source*

---

Build and push r6

![Step 8](LAB_12(image)/8.png)

*Local build release r6; `r6: digest: sha256:0a8bb20d…`; config digest 7488bc11 ≠ manifest digest*

---

Proof by digest

![Step 9](LAB_12(image)/9.png)

*describe-images 20.97 MB; rmi, then pull by digest (the manifest from the registry; layers from the local cache)*

---

Derived revision

![Step 10](LAB_12(image)/10.png)

*Derived from the service's revision :2 (the family's latest was an unused :3) → :4, cpu 256 / memory 1024 / both roles kept*

---

Deployed by hand

![Step 11](LAB_12(image)/11.png)

*ECS pulled `…:r6` from Floci's registry; two tasks running image 7488bc11; `release: r6` read from inside a task*

---

USMSCodeBuildBase v2

![Step 12](LAB_12(image)/12.png)

*Five statements; GetAuthorizationToken on `*`; eight ECR actions on one repository; v2 default*

---

Let the build run Docker

![Step 13](LAB_12(image)/13.png)

*python:3.12-slim (not standard:7.0, the Lab 11 404), privilegedMode true, IMAGE_REPO_URI; source still CODEPIPELINE*

---

The merged buildspec

![Step 14.1](LAB_12(image)/14.1.png)

*The diff shows only additions to my Lab 11 buildspec; the local run built and pushed r6 – with a NEW digest (2bae3b36): builtAt changes every build*

---

Shipped source

![Step 14.2](LAB_12(image)/14.2.png)

*Dockerfile and .dockerignore in the archive; the tag r6 moved while the tasks still ran the old image*

---

USMSCodePipelineBase v2

![Step 15](LAB_12(image)/15.png)

*Six statements; v2 default*

---

The Deploy stage

![Step 16](LAB_12(image)/16.png)

*get → modify → put: Source (S3, no input) → Build (CodeBuild ← SourceOutput) → Deploy (ECS ← BuildOutput)*

---

r7 and the pipeline run

![Step 17.1](LAB_12(image)/17.1.png)

*r7 pushed (b9d0c9c2); Source Succeeded, Build Succeeded, Deploy Failed*

---

Why Deploy failed

![Step 17.2](LAB_12(image)/17.2.png)

*"Provider ECS is not available in Floci CodePipeline"; the service stayed on :4*

---

The deploy action, replayed

![Step 17.3](LAB_12(image)/17.3.png)

*imagedefinitions.json → :5 (r6 → r7), release r7 from inside the tasks; the evidence file says who deployed*

---

The rollback drill

![Step 18.1](LAB_12(image)/18.1.png)

*:6 names r8: registry 404 manifest unknown, "Failed to start ECS task"; rollout IN_PROGRESS, no circuit breaker; r7 tasks kept serving*

---

Rolled back

![Step 18.2](LAB_12(image)/18.2.png)

*Service back on :5, release r7; :6 still ACTIVE at that point*

---

Revision 6

![Step 18.3](LAB_12(image)/18.3.png)

*188 retries, then none after the rollback; the audit flags :6 MISSING; :6 deregistered*

---

Blue/green on paper

![Step 19](LAB_12(image)/19.png)

*appspec (5 hooks) and deployment group (BLUE_GREEN, two target groups) valid; controller ECS*

---

configs/lab-12.env

![Step 20](LAB_12(image)/20.png)

*26 exports; revision lines corrected to the service's :5 (Floci returned the INACTIVE :6 as the family's latest)*

---

Verification

![Section 8](LAB_12(image)/21.png)

*PASS=45 FAIL=0 for the main lab (after Exercise 4 made policy v3 the default: 44/1, the one failure being "default is v2")*

---

The exercise screenshots are in [`Exercise.md`](Exercise.md).

### 6.2 AWS Console Verification

Floci has no console. Everything was verified by readback (`describe-images`, `describe-task-definition`, `describe-services`, `get-pipeline-state`, `simulate-principal-policy`), by Floci's own log (registry requests, image pulls, task-start failures) and by `docker exec` into the running tasks. On real AWS the same evidence would come from the ECR console (image tags and digests), the ECS service's Deployments and Events tabs, and the CodePipeline execution history.

## 7. Analysis and Discussion

**What Floci did for real.** Unlike Lab 11, this lab's data plane worked: Floci's ECR is a real Docker Distribution registry (push, pull by digest, `404 manifest unknown`, and enforced tag immutability in Exercise 2), and Floci's ECS pulled images from it and ran containers whose contents I could read.

| Finding | Evidence | Meaning |
|---|---|---|
| A rebuild of r6 had a new digest | 0a8bb20d → 2bae3b36 | `builtAt` makes every build unique; with MUTABLE tags, **r6 moved under running tasks** |
| The old manifest disappeared | only one r6 digest listed | real ECR keeps it untagged; the image the tasks started from left the registry |
| The pipeline cannot deploy | `Provider ECS is not available in Floci CodePipeline` | the course's 2.0.1 Known Issue still holds on 2.4.0; revision 5 was registered by me |
| An unpushed image fails for real | registry 404, `Failed to start ECS task` ×188 | the circuit breaker is stored, not enforced: no FAILED state, no automatic rollback |
| The API hid what was serving | only the `:6` deployment listed while r7 tasks ran | `docker ps` was the only accurate view |
| The family lookup returned INACTIVE `:6` | `describe-task-definition usms-enrolment` | AWS documents "the latest ACTIVE revision"; derive from the service instead |
| 5100 was in use | `bind: address already in use` | remapped; the registry turned out to be on 4566 |

**Changes I made to the lab, and why.** The lab's Step 14 rewrites `buildspec.yml`, which would have deleted my Lab 11 checks (the parsed container check, the fixed port check, the `finally` summary); I merged Lab 12's additions instead. Step 13 would have restored the `standard:7.0` image Lab 11 proved cannot be pulled; I kept `python:3.12-slim`. Step 10 derives from the family's latest revision; I derived from the service's revision, because the family held an unused revision 3.

**Floci vs real AWS.**

| | Real AWS | Floci 2.4.0 |
|---|---|---|
| ECR push/pull, digests, immutability | full | **real** (Distribution registry on 4566) |
| ECS tasks from your image | full | **real containers** |
| CodePipeline ECS deploy action | full | **absent** |
| Circuit breaker, rolloutState FAILED, service events | full | stored only / absent |
| Untagged images after a tag moves | kept until a lifecycle rule | dropped |
| IAM evaluation | enforced | stored; `simulate-principal-policy` evaluates documents |
| CodeDeploy blue/green | full | API answers; not performed |

## 8. Reflection

**What I learned.** The difference between a tag and a digest stopped being theory: in one afternoon the tag `r6` silently changed under running tasks, and in Exercise 5 I moved `r7` without any deployment and showed that the task definition, the service and the pipeline history could no longer say which bytes were running. I also learned to derive a task definition rather than write one, and that "rollback" in ECS is simply naming an older revision.

**Challenges.** Port 5100 being in use stopped Floci from starting; the fix (a different host range) led to the discovery that the registry was on 4566 anyway. The pipeline's Deploy stage failing taught me to read the exact error rather than assume – my first explanation (no artifact) was wrong, and the real one was that the provider does not exist. In Exercise 4 my first simulation denied a legitimate request, which turned out to be a missing condition key in the test, not a policy bug.

**Real-world use.** I would pin task definitions to digests, make the repository immutable with unique build tags, keep a ledger of tag → digest, audit ACTIVE revisions for images that no longer exist, and put a manual approval before Deploy for production.

## 9. Conclusion

An image built from the enrolment service's own source was pushed to ECR, pulled by ECS and verified from inside the running tasks for two releases. The pipeline was extended to three stages with versioned, scoped policies; on this emulator its Deploy stage cannot run, so the deploy action's documented mechanism was replayed and labelled honestly. A real failed rollout was observed and rolled back by hand, blue/green was specified and scaffolded but not performed, and verification passed 45 of 45 for the main lab.

## 10. Appendix

### Additional Files

- `labs/lab-11-cicd/app/Dockerfile`, `.dockerignore`, `buildspec.yml` (merged; `buildspec.yml.lab08a` is the Lab 11 version)
- `policies/usms-codebuild-policy-v2.json`, `usms-codepipeline-policy-v2.json`, `usms-codepipeline-policy-v3.json` (Ex 4)
- `templates/lab-12-taskdef-v3.json`, `lab-12-codebuild-update.json`, `lab-12-pipeline.json`, `lab-12-appspec.yaml`, `lab-12-codedeploy-deployment-group.json`
- `scripts/utilities/deploy-support-probe.sh`, `usms-ecs-watch.sh`, `verify-lab-12.sh`; `scripts/cleanup/lab-12-cleanup.sh` (not run)
- `docker-compose.yml` (5200–5204), `configs/lab-12.env`, `notes/lab-12-notes.md`, `labs/lab-12-cicd-deploy/Exercise.md`
- Simulator: `USMS Lab 12 - ECS pipeline deploy.json`

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