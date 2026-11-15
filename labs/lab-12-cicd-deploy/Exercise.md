# Lab 12 Independent Exercises

---

## Exercise 1: A Second Base Image, and a Smaller One

I rebuilt the same `dist/` (release r7, `VERSION` unchanged) on Lab 04's base image `public.ecr.aws/nginx/nginx:stable-alpine` and pushed it as `r7-alt`. It was not deployed.

| | r7 (`nginx:1.27-alpine`) | r7-alt (`public.ecr.aws/nginx/nginx:stable-alpine`) |
|---|---|---|
| ECR `imageSizeInBytes` (compressed) | **20,972,450** | 26,076,735 |
| local `docker image inspect` (uncompressed) | **48.2 MB** | 62.4 MB |
| layers | 9 | 9 |
| my application layer (`COPY dist/`) | 823 B | 823 B |

![Exercise 1](LAB_12(image)/ex1.1.png)

**The "alternative" is the larger image.** The whole difference is in the base: `stable-alpine` is a newer nginx release whose main `RUN` layer alone is 49.6 MB and which ships extra modules (`ENV ACME_VERSION` – a certificate module 1.27 does not have). `stable-alpine` is also itself a mutable tag, so "Lab 04's placeholder" is not necessarily the image this pull fetched.

**Why the two sizes differ.** `describe-images` reports the **compressed** size of the layers as stored in the registry; `docker image inspect` reports the **uncompressed** size on disk, so the registry figure is always smaller. That is most of the difference; the rest is that the local daemon shares layers between images and reports each image's full unpacked size, while the registry figure is per manifest.

---

## Exercise 2: Argue for Immutable Tags, Then Implement It

`aws ecr put-image-tag-mutability --image-tag-mutability IMMUTABLE`, then an attempt to push a different image as `r7`:

> `tag invalid: The image tag r7 already exists in the usms-enrolment repository and cannot be overwritten because the tag is immutable.`

`r7` still resolved to `sha256:b9d0c9c2…` and the original remained pullable by digest. **Floci enforced immutability** (the lab expected enforcement to be build-dependent).

![Exercise 2 - the rejected overwrite](LAB_12(image)/ex2.1.png)

**The buildspec change.** With immutable tags, `r7` can be pushed once – and as Step 14 showed, every rebuild produces a different digest, so a second push of `r7` would be refused. The tag must be unique per build. One variable now drives the build, the push, `build-metadata.json` and `imagedefinitions.json`:

```yaml
      - IMAGE_TAG="$USMS_RELEASE-${CODEBUILD_BUILD_NUMBER:-local$(date -u +%Y%m%d%H%M%S)}"
```

CodeBuild sets `CODEBUILD_BUILD_NUMBER`; the local runner does not, so the fallback is `local` plus a UTC timestamp – unique, and visibly not a CI build. The local run pushed `r7-local20261115115030` into the immutable repository (a new tag cannot collide) and `imagedefinitions.json` named it; 8/8 smoke tests.

![Exercise 2 - unique tags](LAB_12(image)/ex2.2.png)

**What immutable tags buy:** a tag names one image forever, so a tag in a task definition, a ticket or an audit always means the same bytes – the silent move of `r6` under running tasks in Step 14 becomes impossible. **What they cost:** tags stop being human release names (release + build number), old tags accumulate and need lifecycle rules, and "re-push to fix" no longer works – a fix is a new tag and a new deployment.

**Final state: MUTABLE.** I set the repository back to MUTABLE at the start of Exercise 5, which needs to move a tag, and because it is the state the course and `verify-lab-12.sh` assume. Recorded here so a later lab is not surprised.

---

## Exercise 3: Build the Blue/Green Scaffolding

| Resource | How it was made | Result |
|---|---|---|
| `usms-enrolment-tg-green` | settings **read from** `usms-enrolment-tg` and passed to `create-target-group` | `ip`, HTTP:80, health `/`, matcher 200, same VPC – identical apart from the name |
| test listener | `create-listener` on `usms-enrolment-alb`, port 8080, forward to green | listeners: **80 → blue (production)**, **8080 → green (test)** |
| deployment group document | the two listener ARNs substituted with python3 | valid JSON, **0** angle-bracket placeholders |

The ECS service's deployment controller was not changed (still `ECS`); Step 19's warning applies – switching to `CODE_DEPLOY` means recreating the service.

![Exercise 3 - target groups](LAB_12(image)/ex3.1.png)

![Exercise 3 - listeners and document](LAB_12(image)/ex3.2.png)

A real setup would also open port 8080 on `usms-alb-sg` **only to the testers' address range**, never `0.0.0.0/0` – the point of a test listener is that production users cannot reach the new version before traffic is shifted. I did not open it (Floci does not enforce security groups, and Lab 09 audits them); it is recorded as a requirement.

---

## Exercise 4: Close the Hole in the Pipeline Policy

**The attack (v2 as written).** A compromised pipeline role can register a new revision of `usms-enrolment` whose container runs any image (a public image needs no ECR permission) or any command, name `usms-ecs-task-role` – passable to `ecs-tasks.amazonaws.com` by design – and point `usms-enrolment-svc` at it with `UpdateService`. The attacker's code then runs as `usms-ecs-task-role`, which carries `USMSStudentDataReadWrite` (Lab 01), and can read, rewrite or delete every student transcript and send them out through the tcp/443 egress Lab 09 still allows. PassRole limited *which* role could be handed over; nothing limited *what code* it runs.

**What the documentation allows** (AWS Service Authorization Reference, "Actions, resources, and condition keys for Amazon Elastic Container Service", `docs.aws.amazon.com/service-authorization/latest/reference/list_ecs.html`):

| Action | Resource type | Condition keys (relevant) |
|---|---|---|
| `ecs:RegisterTaskDefinition` | **`task-definition*`** | `ecs:privileged`, `ecs:task-cpu`, `ecs:task-memory`, `ecs:compute-compatibility`, tags – **nothing for image, command or environment** |
| `ecs:UpdateService` | `service*` | **`ecs:task-definition`** (ARN), `ecs:cluster`, … |
| `ecs:DescribeTaskDefinition` | none | – |

So the lab's statement that `RegisterTaskDefinition` "effectively must be" on `*` is not right: it **can** be scoped to the family ARN. Only the read actions need `*`.

**v3** (`policies/usms-codepipeline-policy-v3.json`, set as default; versions before: 2):

| Statement | Effect |
|---|---|
| `RegisterTaskDefinition` on `task-definition/usms-enrolment:*` with `NumericLessThanEquals ecs:task-cpu 256, ecs:task-memory 1024` | only the enrolment family, only its size |
| Deny `RegisterTaskDefinition` when `ecs:privileged` = `true` | no privileged containers |
| `UpdateService` on the one service with `ArnLikeIfExists ecs:task-definition usms-enrolment:*` | the service can only be pointed at enrolment revisions |
| `DescribeTaskDefinition`, `ListTaskDefinitions` on `*` | they have no resource type |

![Exercise 4 - v3](LAB_12(image)/ex4.1.png)

**Tested with the policy simulator** (Floci evaluates policy documents, Lab 09):

| Request | Decision |
|---|---|
| register `usms-enrolment`, cpu 256 + memory 1024 (a real request) | **allowed** |
| register `usms-enrolment`, cpu 4096 + memory 1024 | implicitDeny |
| register with the memory key missing | implicitDeny |
| register `attacker-tools`, normal size | implicitDeny |
| register a privileged container | **explicitDeny** |
| update the service to a `usms-enrolment` revision | **allowed** |
| update the service to another family | implicitDeny |

My first simulation denied the legitimate registration. The cause was the test: `NumericLessThanEquals` on two keys requires both, and I supplied only `ecs:task-cpu` – a missing key makes a non-`IfExists` condition false. Supplying both keys gave the results above. (A consequence of the design: a task definition with no task-level cpu/memory cannot be registered at all – the safe direction.)

**"Must not break the pipeline":** an execution after v3 gave Source Succeeded, Build Succeeded, Deploy Failed with the **same** `Provider ECS is not available` summary as before v3 – no new failure (and Floci does not enforce IAM in any case).

![Exercise 4 - simulator and execution](LAB_12(image)/ex4.2.png)

**Conclusion: the real hole cannot be closed with IAM alone.** v3 closes the cheap escapes (another family, pointing the service elsewhere, oversized tasks for mining, privileged containers), but no condition key exposes a task definition's image, command or environment, so the role can still register `usms-enrolment:N` running any public image as `usms-ecs-task-role`. That needs controls elsewhere: egress that reaches only ECR through a VPC endpoint (no public registries); a task role without `DeleteObject` and with only the access the service needs (Lab 09's finding); image provenance (signed images verified before deployment, or a deploy that accepts only the digest the build produced); and a manual approval before Deploy.

---

## Exercise 5: Prove a Release End to End, for an Auditor

`outputs/lab-12-release-evidence.md` was generated by a python3 script that ran each command and wrote the command beside its output.

| Link | Evidence | Proven? |
|---|---|---|
| source → r7 | source version `448a75df…` downloaded: `VERSION = r7` | yes |
| source → execution | `get-pipeline-execution cf458f66` → `artifactRevisions[].revisionId = 448a75df…` | **yes – CodePipeline recorded which source version it consumed** |
| execution → build | builds `:10`, `:11` exist but built nothing; r7 was built by the local runner (`buildId: local`) | **no** – the missing link on Floci |
| image → digest | `r7` = `sha256:b9d0c9c2…`; the containers' own `build-metadata.json` names `…:r7` | yes |
| digest → revision → service | `usms-enrolment:5` names `…:r7`; the service runs `:5` | by **tag** only |
| what is running | containers `835ec484…` serve `"release":"r7"` | yes |

**Breaking one link.** I set the repository to MUTABLE and pushed the `r7-alt` image as `r7` (not deployed). The ledger `outputs/lab-12-image-digest.txt` now has two `r7` lines: `b9d0c9c2…` (11:31) and `f3908257…` (11:59).

| Evidence after the retag | Says |
|---|---|
| revision 5 | still `…/usms-enrolment:r7` – unchanged text |
| the service | still `:5` |
| the running containers | image `835ec484…` |
| what `r7` now resolves to | image `4ef3d1b0…` |

![Exercise 5](LAB_12(image)/ex5.2.png)

**What the document can still prove:** which source version said r7, which execution consumed it, which revision the service runs, and – from inside the containers – which release they serve. **What it can no longer prove:** which bytes revision 5 runs. It names a tag, the tag now names different content, and nothing was deployed. If a task restarted, it would pull the alt image and change what runs without a revision, a deployment or a pipeline execution; only the ledger records that the tag moved. **A task definition naming the digest** (`…/usms-enrolment@sha256:b9d0c9c2…`) would close the link – this is the answer to Section 14 Q7.

---

## Summary

| Exercise | Result |
|---|---|
| 1 | r7 21.0 MB vs r7-alt 26.1 MB (compressed); the difference is the base; 823 B app layer |
| 2 | Floci enforced IMMUTABLE; unique build tags `release-buildnumber`; repository back to MUTABLE (stated) |
| 3 | green target group copied from blue, test listener 8080, deployment group with real ARNs |
| 4 | the attack; documented keys; v3 closes what IAM can; simulator-tested; the image hole needs other controls |
| 5 | evidence chain with the source→execution link proven; a retag breaks the tag→bytes link |