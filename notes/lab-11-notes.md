## Exercises - short record
- Ex 1: usms-results-build (S3 source, SAME usms-codebuild-role, python:3.12-slim). Local build: results r1. Floci build
  SUCCEEDED with no artifact (same gap), batch-get-builds role null. USMSCodeBuildBase covers the bucket but its log
  statement names only /aws/codebuild/usms-enrolment-build -> would need policy v2 on real AWS.
- Ex 2: finally in post_build writes dist/build-summary.txt. First version reported "tests=passed" for a failed build:
  under errexit the status was never written and finally read a stale 0 from the previous run. Fixed with
  "SMOKE=0; bash tests/smoke.sh || SMOKE=$?" and deleting the status file first. Tested with a harness (commands with
  set -e, then always finally) - not observed in CodeBuild.
- Ex 3: parsed JSON container check (passes with 4-space indent; names expected and found); trust policy +
  aws:SourceArn for both projects.
- Ex 4: S3 -> EventBridge delivered and matched one key; target codepipeline unsupported on Floci (before=4 after=4).
- Ex 5: imagedefinitions.json array at the artifact root, name from config/service.json, IMAGE_URI exported with the
  nginx default; 8th smoke assertion; readiness file with "BuildOutput key: NONE".

## Step 15 question - iam:PassRole with Resource "*" but the condition kept
The condition iam:PassedToService still limits WHICH SERVICE receives the role (here codebuild), but "*" removes the
limit on WHICH ROLE. Anyone allowed to call create-project/update-project could then name the most powerful role that
CodeBuild may assume - for example an administrator role, or usms-codepipeline-role / usms-deploy-role - and run
arbitrary buildspec commands with its permissions. Naming the one role (usms-codebuild-role) is what stops a build
from becoming a privilege-escalation path; the condition alone only restricts where the escalation lands.

## Nested heredocs (for the checklist)
<< 'BUILDSPEC' (quoted) writes the text literally, so $USMS_RELEASE and ${CODEBUILD_BUILD_ID:-local} reach the file
for CodeBuild to expand; << META (unquoted, inside it) is expanded at BUILD time; << EOF in Step 21 is expanded at
WRITE time. Quoted writes the text, unquoted writes the result.

## Review Questions

### Q1. Source and Build succeed, the deployed application is unchanged
Explanation 1 - artifacts.base-directory: the build wrote its output to dist/ but base-directory pointed elsewhere (or
files matched nothing), so the artifact is empty or holds the wrong files and the deploy stage has nothing new to
deploy. One command: download the BuildOutput zip and list it (python3 -m zipfile -l, or unzip -l) - an empty or
"dist/"-prefixed listing shows it. Explanation 2 - the source zip's layout: the zip had a top-level app/ directory,
so the build ran against an old or default buildspec (or Floci's inline reading, as I found) and never saw the new
source. One command: unzip -l on the SOURCE zip - every path starting with app/ shows it. (On Floci there was a third,
emulator-specific explanation: the build never received the source at all - shown by build-metadata absence and the
phase contexts.)

### Q2. Why CodePipeline requires versioning on an S3 source
An execution must record WHICH source it is building and keep using that exact source for its whole run, even if
someone uploads a new object a second later. With versioning the Source action records the object's version id; every
later stage of the same execution reads that version, and the execution history can say precisely which bytes produced
which artifact. Without versioning there is only "the object at this key now", so an execution could not identify, nor
consistently re-read, its own input.

### Q3. iam:PassRole to someone who thinks it is redundant
Their objection is fair: they may create the project. But creating a project and choosing which identity it runs as are
different powers. When I name a role for a service, the service will later act WITH THAT ROLE'S PERMISSIONS, not mine.
If naming any role were free, anyone allowed to create a build project could name an administrator role and let the
build do what they themselves may not - a privilege escalation through a service. iam:PassRole asks the separate
question "may you hand THIS role to THAT service?", so the permissions a person can obtain indirectly never exceed the
roles they were explicitly allowed to pass.

### Q4. Two roles vs one
For two roles: they separate blast radii. A compromised build (a malicious dependency in the build container) holds
only usms-codebuild-role: its log group and the artifact bucket. It cannot start other builds, pass roles, or (in Lab 12)
update the ECS service. A compromised pipeline configuration cannot run arbitrary commands. Each role's policy is small
enough to review, and each trust policy names one service. Strongest argument against: the build already WRITES the
artifacts the pipeline deploys, so a compromised build can still ship malicious code through the legitimate path - the
separation protects the AWS account more than it protects the deployed application; and two roles, two policies and a
PassRole statement are more to maintain, where a mistake (as Exercise 1's log statement showed) silently breaks a build.

### Q5. The three heredoc forms
<< 'BUILDSPEC' written as << BUILDSPEC: my shell would expand $USMS_RELEASE, $ARTIFACT_DIR and
${CODEBUILD_BUILD_ID:-local} at WRITE time - to empty strings and "local" - so the buildspec would contain blanks and
always report a local build; YAML stays valid and nothing reports an error. << META written as << 'META': the metadata
file would contain the literal text $USMS_RELEASE instead of r4 - still valid JSON, so json.tool passes. << EOF in Step
21 written as << 'EOF': configs/lab-11.env would contain the command text $(aws ...) instead of values; sourcing it
later would RUN those commands silently (or fail quietly), so values change or go empty without an error. In every case
the result is syntactically valid, which is why no tool complains.

### Q6. Removing pre_build validation because "the deploy stage checks it anyway"
They are right when the deploy stage really checks the same thing early and cheaply, nothing irreversible happens
before it (no image pushed, no artifact published that others consume), and builds are short. They are expensively
wrong when the deploy check happens late: after a slow build and image push, mid-rollout (some tasks already replaced),
or only as a failed health check after the service has started rolling - then the bad configuration costs a rollback,
an incident, or a broken environment, instead of 90 seconds. My Step 20 showed a sharper version: on Floci the pipeline
stayed green with a broken container name; the only check that caught it was pre_build, run locally.

### Q7. Proving r4 was built from the source in the repository on a given date
Evidence chain: (1) the git commit on that date containing labs/lab-11-cicd/app with VERSION r4; (2) the S3 source
object's version id and LastModified for the upload of that zip (list-object-versions), and the zip's contents matching
the commit; (3) the pipeline execution that recorded that source version id; (4) the build id that execution started;
(5) the artifact's build-metadata.json naming release r4, that build id and CODEBUILD_RESOLVED_SOURCE_VERSION = that S3
version. Weakest link: the step from git to S3 - the zip was packed and uploaded by hand from my working tree, so
nothing proves the uploaded bytes equal the committed files (uncommitted changes would be included). Recording a
checksum of the zip with the commit, or building straight from the repository, would close it. On Floci there is a
second weak link: no CodeBuild artifact exists at all, so links 4-5 are only demonstrable with the local runner.