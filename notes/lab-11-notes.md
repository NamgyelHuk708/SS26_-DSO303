# Lab 11 notes

## Support path
USMS_CICD_SUPPORT_PATH=A - Floci 2.4.0.

## Step 12 - Known Issue confirmed on Floci 2.4.0
First standalone build (usms-enrolment-build:1): FAULT in about 5 s. batch-get-builds context and docker logs floci:
"Status 404: pull access denied for aws/codebuild/standard, repository does not exist or may require
'docker login'". aws/codebuild/standard:7.0 is published only inside AWS's CodeBuild fleet, so a local
Docker daemon cannot pull it. FAULT (not FAILED) = CodeBuild could not run the build at all; my buildspec
was never executed. Alternative from the course's Known Issues page (Lab 11): python:3.12-slim.
The buildspec needs only python3, bash, sed, cp and date - all present in Debian's python:3.12-slim.

## Step 12-13 - a SUCCEEDED build that built nothing (python:3.12-slim)
Build usms-enrolment-build:2: status SUCCEEDED, all 11 phases SUCCEEDED in 0 s. But docker logs floci shows
the python:3.12-slim container Started at 16:39:32.853 and Stopping at 16:39:32.992 - it lived 0.14 s, too
short to start Python. The log stream was created and is empty, no "--- install ---" marker appears anywhere,
and NO artifact exists under build/ (the bucket holds only the source zip). Conclusion: on Floci 2.4.0 a green
CodeBuild status is not evidence the buildspec ran. The evidence I rely on instead: the local runner (Step 14,
exit 0, 7/7 smoke tests, buildId "local") and - if the pipeline produces one - the artifact's contents (Step 19).

## Step 8 your-turn - a bug the deliberate failure caught
grep -q '"port": 80' PASSED with "port": 8080 - the pattern is a prefix of the wrong value. Fixed with
grep -qE '"port": 80([^0-9]|$)'; with 8080 the local build now stops in pre_build with my message, exit 1.
Exercise 3 replaces text matching with JSON parsing, which removes this class of bug.

## Step 17 - no automatic first execution
create-pipeline succeeded (2 stages), but get-pipeline-state showed latestExecution None for both stages after
20 s and no SourceOutput object was written. Real AWS starts an execution as soon as a pipeline is created;
Floci 2.4.0 stores the pipeline without starting one. Step 19's start-pipeline-execution is the first run.

## Step 19 - why Floci's builds "succeeded" without building (diagnosed)
Pipeline execution 067a9216: Source Succeeded, Build Succeeded, execution Succeeded on the first poll - but NO
SourceOutput/BuildOutput objects were written and the build container lived 0.21 s. Also, start-build on a
CODEPIPELINE-source project was ACCEPTED (build 3) - real AWS refuses it (Step 18's "cost" not observed).
Experiment (build 6): the same build with --buildspec-override "$(cat buildspec.yml)" (the CONTENT) FAILED with
PRE_BUILD FAILED / POST_BUILD FAILED, container 0.55 s. Conclusion: Floci 2.4.0 treats the project's
source.buildspec value "buildspec.yml" as an INLINE buildspec (a YAML document with no phases) instead of a path
inside the source - so every earlier "SUCCEEDED" ran nothing. A green build status was never evidence.
Follow-up (build 6 contexts, which Floci DOES populate): PRE_BUILD "Exit code 1: VERSION file is missing";
POST_BUILD "Exit code 127: bash: tests/smoke.sh: No such file or directory". My commands ran in the container,
but the S3 source zip was never unpacked into it, although DOWNLOAD_SOURCE reports SUCCEEDED.
=> Floci 2.4.0 CodeBuild: (1) source.buildspec is read as inline YAML, not a path; (2) the S3 source is not
delivered to the container. The control plane is observed (projects, pipeline, executions, states, contexts);
build EXECUTION is evidenced by the local runner from here on (the lab's Path B treatment for Steps 19-20).

## Step 20 - the deliberate failure
Broken source (container "enrolment-api-v2"): pipeline execution d51441d9 -> Source Succeeded, Build Succeeded,
"Action completed."; build usms-enrolment-build:8 SUCCEEDED with no failed phase. The local runner on the same
buildspec: pre_build -> "config/service.json names the wrong container" -> exit 1. On real AWS the pipeline is the
safety net (Build fails in PRE_BUILD, nothing deploys); on Floci 2.4.0 the only check that caught it was the local
runner - "validate locally, then push". Fixed, validated locally, uploaded (5 source versions), executed.

## Exercise 4 - EventBridge trigger: how far the event got on Floci 2.4.0
Bucket EventBridgeConfiguration stored; rule usms-enrolment-source-changed (one key) and target stored; uploading
a new source version made EventBridge deliver and MATCH the event (EventBridgeInvoker ran 30 s after the upload),
but the invoker logged "unsupported target ARN type: arn:aws:codepipeline:...". Executions before=4 after=4.
Observed: S3 -> EventBridge delivery and one-key matching. Not available: a CodePipeline target.
