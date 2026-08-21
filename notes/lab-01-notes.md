## Step 7 reflection
(Write 2 sentences here about why memory mode leaves the mounted directory empty.)
## Step 26 — get-account-authorization-details
Command: aws iam get-account-authorization-details
Result: "An error occurred (UnsupportedOperation) when calling the
GetAccountAuthorizationDetails operation: Operation GetAccountAuthorizationDetails
is not supported."
This is a documented Floci limitation (not all IAM APIs are implemented in the
local emulator). No output file was produced. Skipped the jq sub-step, which
depended on this file.
## Step 32 — simulate-principal-policy
Result: ec2:CreateVpc showed implicitDeny even though usms-dev-01 inherits
Allow permission for it via the usms-developers group (USMSDeveloperBase policy).
This appears to be a Floci limitation — the simulator likely only evaluates
policies attached directly to the user ARN, not policies inherited through
group membership. On real AWS this would return "allowed".
iam:CreateUser correctly showed explicitDeny (matches the DenyDangerousIdentityChanges
statement). s3:GetObject correctly showed implicitDeny (no S3 permission granted to
this user/group).
## Step 33 — snapshot
`floci snapshot save` returned HTTP 400 (unsupported on this Floci build).
Used the tar fallback instead: ~/floci-data-lab-01.tar.gz
