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

## Your Turn — Step 7: storage modes
Q: If --persist mounts a directory correctly, why is the directory almost
   empty in memory mode?
A: --persist only tells Floci WHERE on the host to mount /app/data — it does
   not change FLOCI_STORAGE_MODE. In memory mode, Floci keeps all state in
   RAM and only writes minimal/no data to disk, because it assumes its own
   state is disposable. It also deletes its own Docker volumes on teardown.
   So the directory exists (the mount worked) but stays empty because the
   storage MODE, not the mount, controls what actually gets written to it.

## Your Turn — Step 12: aws configure list
The "Location" column shows where each value came from. The access key and
secret key show "shared-credentials-file" because they were written into
~/.aws/credentials by `aws configure set`, which always stores secrets in
that file (never in ~/.aws/config), regardless of profile.

## Your Turn — Step 17: output formats
table and text return the same underlying data, just formatted differently.
For scripts, `text` is the right choice — it has no quotes/braces/borders,
so it can be captured directly into a shell variable with $(...) without
needing to parse JSON or strip table borders.

## Your Turn — Step 24: create-vpc skeleton
The most important parameter is CidrBlock — it defines the IP address range
of the VPC and cannot be changed after creation. Everything else (tenancy,
IPv6, tags) is optional or can be modified later.

## Your Turn — Step 32: prediction for usms-audit-01
Prediction BEFORE running:
- ec2:CreateVpc      -> implicitDeny (auditors only have ReadOnlyAccess /
                        USMSReadOnly, which contains no write actions)
- ec2:DescribeVpcs   -> allowed (ReadOnlyAccess includes ec2:Describe*,
                        and DescribeVpcs matches that wildcard)

Actual result: (paste table output here)
Match/mismatch explanation: (note if it matches your prediction, or if it's
another instance of the simulator not evaluating group-attached policies)
