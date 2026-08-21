# Lab 01 — IAM — completed

## What exists after this lab
- Environment: Floci via docker-compose.yml, FLOCI_STORAGE_MODE=hybrid,
  bind-mounted to ~/floci-data, persistence proven in Step 14
- Groups: usms-admins, usms-developers, usms-auditors
- Users: usms-admin-01, usms-dev-01, usms-audit-01
- Customer managed policies: USMSDeveloperBase (v2), USMSStudentDataReadWrite,
  USMSAssumeAppRoles, USMSLambdaBasic
- Inline policy: USMSSelfManageCredentials on usms-dev-01
- Roles: usms-ec2-app-role, usms-lambda-exec-role, usms-developer-role
- Instance profile: usms-ec2-app-profile

## Reproduce
    source configs/course.env
    ./scripts/setup/floci-up.sh
    source configs/lab-01.env
    ./scripts/utilities/verify-lab-01.sh

## Evidence
- [x] whoami.sh output showing account 000000000000
- [x] floci-storage-check.sh output, all [ok]
- [x] Step 14 persistence proof (user survived a restart)
- [ ] verify-lab-01.sh with FAIL=0

## Problems I hit and how I fixed them
- Project path is not ~/aws-floci-course but nested under
  ~/Desktop/SEM_7/DSO303/SS26_-DSO303/LAB_1/aws-floci-course — used
  a $COURSE_ROOT variable and relative paths throughout.
- get-account-authorization-details: UnsupportedOperation (Floci limitation)
- floci snapshot save/list: "Snapshot API not available on this server
  version" (Floci limitation) — used tar fallback instead
  (~/floci-data-lab-01.tar.gz)
- simulate-principal-policy: showed implicitDeny for a group-inherited
  permission instead of allowed (Floci limitation, likely doesn't evaluate
  group policies in the simulator)
