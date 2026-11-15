# Lab 12 - files prepared in advance

| File | Step | Notes |
|---|---|---|
| labs/lab-11-cicd/app/Dockerfile, .dockerignore | 7 | as the lab (.dockerignore also excludes the buildspec backups) |
| labs/lab-11-cicd/app/buildspec.lab12.yml | 14 | **MERGED**, not the lab's rewrite: my Lab 11 buildspec (parsed container check, fixed port check, finally summary, IMAGE_URI contract) **plus** Lab 12's guarded registry login, guarded docker build/push and imageUri in build-metadata. IMAGE_URI now defaults to ${IMAGE_REPO_URI}:release. Tested with the local runner: 8/8 smoke tests |
| policies/usms-codebuild-policy-v2.json | 12 | as the lab |
| policies/usms-codepipeline-policy-v2.json | 15 | as the lab |
| templates/lab-12-appspec.yaml, lab-12-codedeploy-deployment-group.json | 19 | as the lab (conceptual) |
| scripts/utilities/deploy-support-probe.sh, usms-ecs-watch.sh | 3, 11 | as the lab |
| scripts/utilities/verify-lab-12.sh | 8.1 | 45 checks; .gitkeep fix |
| scripts/cleanup/lab-12-cleanup.sh | 8.2 | NOT RUN; deregisters 3..latest (not a fixed 3-5) and uses python:3.12-slim |

Written live: docker-compose.yml edit (Step 4), templates/lab-12-taskdef-*.json (10), templates/lab-12-codebuild-update.json (13 - needs the ECR URI; image python:3.12-slim, NOT standard:7.0), templates/lab-12-pipeline*.json (16), configs/lab-12.env (20).
