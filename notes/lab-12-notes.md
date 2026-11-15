# Lab 12 notes

## Support path
USMS_CICD_DEPLOY_PATH=A USMS_CODEDEPLOY_SUPPORTED=yes - Floci 2.4.0.

## Step 14 - the tag moved under a running service
Step 8 pushed r6 = sha256:0a8bb20d...; Step 14's local runner rebuilt r6 = sha256:2bae3b36... The build stamps
builtAt into build-metadata.json and index.html, so the content (and the digest) changes on every build - the
build is not reproducible by design. The repository is MUTABLE, so the tag r6 moved to the new image, while the
running tasks still run the old one (image 7488bc11...). "r6" no longer identifies what is running; only a
digest does. This is Section 14 Q3 and Exercise 2, observed rather than argued.
Also: after the tag moved, describe-images lists only the new digest. Real ECR keeps the old manifest as an
UNTAGGED image; Floci 2.4.0 dropped it, so the image the running tasks were started from is no longer in the
registry (pull by the old digest - result recorded below).

## Step 17 - the pipeline cannot deploy on Floci 2.4.0
Execution cf458f66: Source Succeeded, Build Succeeded, Deploy FAILED - action summary "Provider ECS is not available
in Floci CodePipeline" (the course's Lab 12 Known Issue for Floci 2.0.1, still present on 2.4.0). The service stayed
on usms-enrolment:4; 0 pipeline artifact objects. (Even with the provider, there would be no BuildOutput to read -
Lab 11.) I replayed the deploy action's documented mechanism by hand with the local build's imagedefinitions.json:
read the service's revision (:4), replace the image of the container it names, register (:5), update the service.
Result: release r7 served from inside the tasks. Revision 5 was registered by ME, not by the pipeline.

## Step 18 - the rollback drill, really failing
Revision :6 names r8, which was never pushed. Floci's registry (a real Docker Distribution registry,
floci-aws-floci-course-ecr-registry:5000) answered HEAD/GET manifests/r8 with 404 "manifest unknown"; EcsService:
"Failed to start ECS task ... manifest ... r8 not found" (= CannotPullContainerError). The deployment stayed
PRIMARY :6, running 0, rolloutState IN_PROGRESS, no service events - the circuit breaker is stored, not enforced:
no FAILED state, no automatic rollback. The two r7 tasks (image 835ec484) kept running, so there was no outage -
but describe-services listed only the :6 deployment, so the API did not show what was actually serving.

## Step 18 your turn - revision 6
Decision: DEREGISTERED usms-enrolment:6 (now INACTIVE). It names r8, which was never pushed, so it can only ever
fail; INACTIVE means nobody can deploy it by mistake, while it stays readable (describe-task-definition) as the
record of the drill. How someone notices such a revision in six months without being told: the audit loop above
(every ACTIVE revision's image checked with ecr describe-images) flagged :6 as MISSING immediately - run it in
verification or CI and the gap is visible. Revision :3 (the external placeholder, never run by the service) would
be listed too; I left it, as it belongs to an earlier lab.
Correction: revision :3 did NOT appear in the ACTIVE list - it was already INACTIVE (deregistered in an earlier lab).
Floci finding: after deregistering :6, describe-task-definition --task-definition usms-enrolment still returned :6
(INACTIVE) as the family's latest; real AWS returns the latest ACTIVE revision (:5). lab-12.env's revision lines
were therefore set from the SERVICE's task definition (:5) instead of the family lookup.
