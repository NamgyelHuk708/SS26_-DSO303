# Lab 11 - files prepared in advance (unzipped into the repo)

| File | Step | Notes |
|---|---|---|
| labs/lab-11-cicd/app/VERSION, src/index.html, src/healthz.html, config/service.json, tests/smoke.sh | 7 | exactly as the lab (VERSION = r3) |
| labs/lab-11-cicd/app/buildspec.yml | 8 | exactly as the lab; PyYAML parse OK |
| policies/trust-codebuild.json, usms-codebuild-policy.json | 9 | as the lab |
| templates/lab-11-codebuild-project.json | 10 | serviceRole filled in (arn:aws:iam::000000000000:role/usms-codebuild-role) - no $ |
| policies/trust-codepipeline.json, usms-codepipeline-policy.json | 15 | as the lab |
| templates/lab-11-pipeline.json | 16 | roleArn filled in - no $ |
| scripts/utilities/cicd-support-probe.sh | 3 | as the lab |
| scripts/utilities/usms-pack-source.sh | 11 | as the lab; tested: buildspec.yml at the zip ROOT, dist/ excluded |
| scripts/utilities/usms-buildspec-run.sh | 14 | as the lab; tested with PyYAML and with the built-in parser: 4 phases, 7/7 smoke tests, exit 0 |
| scripts/utilities/verify-lab-11.sh | 8.1 | 46 checks; two fixes: image check also accepts the Known Issues image python:3.12-slim, and the .gitkeep check |
| scripts/cleanup/lab-11-cleanup.sh | 8.2 | NOT RUN |

Written live: configs/lab-11.env (Step 21), notes/lab-11-notes.md, outputs/*, and your Step 8 "Your turn" port check.
