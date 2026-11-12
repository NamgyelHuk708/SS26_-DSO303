# Lab 09 – files prepared in advance (unzipped into the repo)

| File | Used in | Notes |
|---|---|---|
| policies/usms-student-data-ro-policy.json | Step 7 | static |
| policies/trust-ecs-tasks-scoped.json | Step 7 | account 000000000000 and us-east-1 already filled in (from configs/lab-01.env / course.env) |
| policies/usms-permissions-boundary.json | Step 8 | static |
| policies/usms-deploy-policy.json | Step 8 | the three role ARNs already filled in |
| policies/trust-deploy.json | Step 8 | user/usms-admin-01 already filled in |
| policies/usms-db-sg-egress.json | Step 15 | static |
| policies/usms-egress-allow-all.json | Step 13 | the undo document |
| scripts/utilities/usms-iam-audit.sh | Step 5 | as on the lab page |
| scripts/utilities/usms-sg-audit.sh | Step 12 | as on the lab page |
| scripts/utilities/usms-reachability-matrix.sh | Step 17 | as on the lab page |
| scripts/utilities/verify-lab-09.sh | Section 8.1 | two fixes: the boundary-attachment check (nested quotes made it impossible to pass) and the .gitkeep check |
| scripts/cleanup/lab-09-cleanup.sh | Section 8.2 | NOT RUN |
| scripts/utilities/usms-eks-rebuild.sh | after Step 18 | rebuilds the Lab 07/08 Kubernetes state that a Floci restart wipes |

Written live during the lab, because they need IDs only known at run time:
policies/usms-enrolment-sg-egress.json (Step 13, prefix list), policies/usms-alb-sg-egress.json
(Step 14, enrolment SG), policies/usms-app-sg-ssh-bastion.json (Step 16, bastion SG), configs/lab-09.env,
and everything in outputs/.
