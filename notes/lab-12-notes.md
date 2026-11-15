## Step 16 your turn - Deploy reading SourceOutput instead of BuildOutput
SourceOutput is the source zip: buildspec.yml, VERSION, src/, config/, tests/, Dockerfile - no dist/ and therefore no
imagedefinitions.json at its root (only the build writes it, into dist/, which artifacts.base-directory makes the
root of BuildOutput). The Deploy action would look for imagedefinitions.json at the root of the source archive, not
find it, and fail in the DEPLOY stage - although the mistake is in the pipeline wiring between Build and Deploy, and
Build itself would report Succeeded.

## Step 12 your turn
Not written before reading Step 15. Comparing afterwards: the two non-obvious choices are RegisterTaskDefinition on
"*" (I would have tried a task-definition ARN - which, it turns out, the documentation allows; see Exercise 4) and
iam:PassedToService ecs-tasks.amazonaws.com (the TASKS receive the roles, not the ECS service).

## Review Questions

### Q1. Three changes that cannot travel through the ECS deploy action
The action copies the running revision and changes only the image of the named container. (1) More memory or CPU
for the task: deploy by registering a revision with the new size (derived, as in Step 10) and updating the service -
by hand, or with an infrastructure template (CloudFormation) that owns the task definition. (2) A new or changed
environment variable or secret reference: same route - a new revision registered from a reviewed document; better,
the task definition kept as a file in the repository and rendered by the build (the CodeDeploy route uses a task
definition file and appspec.yaml). (3) A changed log configuration, health check, or a second container (a sidecar):
again a new revision from a document, because the action can only swap one image. In all three, the change is to the
task definition itself, so it has to be deployed as one - which is why teams move the task definition into the
repository and let the pipeline register it, rather than relying on the copy-and-swap action.

### Q2. GetAuthorizationToken on "*" vs RegisterTaskDefinition on "*" - the same kind of exception?
For "the same": both are actions whose natural target is not a specific existing resource - a registry-wide token,
and a revision that does not exist yet - so both look like "there is nothing to name". Against: GetAuthorizationToken
truly has no resource type; it returns a token that is useless on its own, and what can be pulled or pushed is still
limited by the repository-scoped actions in the same policy. RegisterTaskDefinition, as the Service Authorization
Reference shows, DOES have a resource type (task-definition*) and can be scoped to a family ARN, plus cpu, memory and
privileged conditions - and what it creates is directly dangerous (any image, any command, a passable role). My
answer: they are NOT the same kind. The token on "*" is a genuine, low-risk exception; RegisterTaskDefinition on "*"
is a convenience that should be narrowed (v3), and even narrowed it leaves the image uncontrollable by IAM.

### Q3. Digest vs tag
For the colleague: a tag is a name that anyone with push permission can move; a digest is computed from the content
and cannot. I watched this happen twice - r6 moved to a new image while the tasks ran the old one (Step 14), and I
moved r7 on purpose without a deployment (Exercise 5). A task definition naming a digest runs exactly the bytes that
were tested, can be audited, and cannot change when a task restarts. The strongest case AGAINST pinning digests: it
removes the ability to pick up a fix by re-tagging - every patch, including an urgent base-image security fix, now
requires a new task definition revision and a deployment; digests are unreadable to humans, so mistakes in reviews
are harder to spot; and the pipeline must carry the digest from the push to the deploy, which is extra machinery
that can itself break. (The usual compromise: immutable tags that are unique per build - Exercise 2 - which give
digest-like stability with readable names.)

### Q4. A failure the circuit breaker would not catch
The breaker trips on tasks that fail to START or fail health checks during a deployment. It would not catch an image
that starts, passes its health check (Lab 05's check is just GET / returning 200), and then behaves wrongly - for
example a release that serves the portal but writes corrupted enrolment records, or returns stale transcripts, or is
much slower. Mechanisms that would: a meaningful health check that exercises a real dependency; CloudWatch alarms on
application metrics (5xx rate, latency, error logs) attached to the deployment - ECS deployment alarms, or CodeDeploy
blue/green with DEPLOYMENT_STOP_ON_ALARM and automatic rollback (Step 19's document); and the blue/green test listener,
which lets a smoke test run against the new version before any production traffic reaches it.

### Q5. Why replace-only, and what a merge would have to decide
All four configure ONE coherent document whose parts depend on each other: a pipeline's stages and artifact names,
a bucket's notifications, a trust policy's statements, a bucket policy. Replacing the whole document lets the service
validate it as a unit and makes the result exactly what was sent - no hidden leftovers. A merge-based update-pipeline
would have to decide: how to identify a stage (by name? by position?), what an omitted stage means (delete it or keep
it?), how to merge actions inside a stage and their runOrder, what to do when an inputArtifact refers to an output that
the merge removed, how to resolve two concurrent edits, and how to delete anything at all. Replace-only pushes those
decisions to the caller - which is why get-modify-put, with the assertions in Step 16, is the safe pattern.

### Q6. Why create-policy-version is not default-by-default
Because creating a version and activating it are different decisions. The workflow it protects: write v2, read it
back, review or simulate it (simulate-principal-policy - as I did for v3) while every principal still runs on the
known-good v1, and only then promote it with set-default-policy-version. If something breaks, rollback is one call:
set the default back to v1 - the old version is still there (up to five are kept). If creating meant activating, a
typo would hit every attached principal the instant the call returned. This lab showed the cost of forgetting the flag
too: the verify check "default is v2" exists precisely because that mistake is silent.

### Q7. "The enrolment service is running code that was never reviewed"
outputs/lab-12-deploy-evidence.txt helps: it ties the service's revision (:5) to an image reference (…:r7) and to who
performed the deploy. The pipeline execution history helps for the source side: execution cf458f66 recorded the
source version it consumed (448a75df, VERSION r7), which can be matched to a reviewed commit. outputs/lab-12-image-
digest.txt helps most with the gap but cannot settle it alone: it shows the tag r7 has pointed at two digests
(b9d0c9c2, then f3908257). What does NOT settle it: anything that names only the tag - revision 5, imagedefinitions.json,
the service. To settle it in one command I would need, recorded at build time, the immutable link from reviewed source
to running bytes: the image DIGEST written into the task definition (image@sha256:…) or into imagedefinitions.json,
plus the source version / commit inside the image (build-metadata.json with sourceVersion, which on Floci was "local").
Then one command - describe-task-definition on the running revision, compared with the digest the build recorded for
the reviewed commit - answers it.