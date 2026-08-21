# AWS Practical Laboratory Report Lab 1: Identity and Access Management (IAM)

---

## 1. Aim / Objective

The aim of this lab was to learn how AWS IAM is used to manage users, groups, roles, and policies. I used the AWS CLI together with Floci (a local AWS emulator) to create and test an IAM setup, without needing a real AWS account.

## 2. Introduction

IAM (Identity and Access Management) is the AWS service that controls who can do what in an AWS account. It is a global service, meaning it is not tied to any one region. IAM lets an administrator create users, put them into groups, and attach policies that say what actions are allowed or denied. IAM also supports roles, which give temporary access instead of permanent credentials.

Key things I used in this lab:
- IAM Users
- IAM Groups
- IAM Roles
- IAM Policies (managed, customer managed, and inline)
- IAM Policy Versions
- AWS STS (temporary credentials)
- Access Keys

## 3. Use Case

This lab used a fictional university system called USMS (University Student Management System). Instead of giving everyone full access, different groups were created for different jobs:

| Group | Who | Permissions |
|---|---|---|
| usms-admins | Lead cloud engineer | Broad, course scoped access |
| usms-developers | Developers building infrastructure | Build and inspect USMS resources |
| usms-auditors | University auditor | Read only access everywhere |

There were also three roles for things that are not people:

| Role | Used by | Purpose |
|---|---|---|
| usms-ec2-app-role | The application server | Read/write student data in S3 |
| usms-lambda-exec-role | Notification functions | Logs and messaging |
| usms-developer-role | Developers, temporarily | Elevated build permissions |

This setup follows the principle of least privilege. Each identity only gets the permissions it actually needs.

## 4. Implementation Procedure

A separate architecture diagram was not built for this lab, since it was not required.

Docker, Floci, and the AWS CLI were set up first. Then came the project folder and Git, with a .gitignore file added before creating any secrets so nothing sensitive could get committed by mistake.

After that, the actual IAM setup was built. Three groups and three users were created, each user was added to its group, and policies were attached to control what they could do. Three roles were then created and tested, including getting temporary credentials through STS. Finally, an access key was created safely, and a script was run to verify that everything was working correctly.

The Your Turn practice tasks placed through the lab were also completed, along with the Independent Lab Exercises at the end.

## 5. Results and Evidence

### 5.1 Environment Setup (Part A)

**Docker / Compose check**

![Step 2](LAB_1(image)/step_2.png)

**Project folder structure created**

![Step 5](LAB_1(image)/step_5.png)

**.gitignore and first Git commit**

![Step 6](LAB_1(image)/step_6.png)

**Floci started via Docker Compose**

![Step 9](LAB_1(image)/step_9.png)

**AWS CLI profile configured**

![Step 12](LAB_1(image)/step_12.png)

**whoami.sh confirming identity and account**

![Step 13](LAB_1(image)/step_13.png)

**Isolation test, stopping Floci breaks the CLI**

![Step 14.3](LAB_1(image)/step_14.3.png)

**Persistence test, user survived a container restart**

![Step 14.4](LAB_1(image)/step_14.4.png)

**Storage diagnostics, all checks passed**

![Step 15.2](LAB_1(image)/step_15.2.png)

**Part A wrap up / commit**

![Step 15](LAB_1(image)/step_15.png)

### 5.2 IAM Foundation (Part B)

**Groups created (usms-admins, usms-developers, usms-auditors)**

![Step 18](LAB_1(image)/step_18.png)

**Users created and tagged**

![Step 19](LAB_1(image)/step_19.png)

**AWS managed policy attached to auditors**

![Step 21](LAB_1(image)/step_21.png)

**Developer base policy created and attached**

![Step 22](LAB_1(image)/step_22.png)

**S3 student data policy created**

![Step 23](LAB_1(image)/step_23.png)

**Full identity inspection of usms-dev-01**

![Step 26](LAB_1(image)/step_26.png)

**Policy version bumped (v1 to v2)**

![Step 27](LAB_1(image)/step_27.png)

**EC2 role, trust policy, and instance profile**

![Step 28](LAB_1(image)/step_28.png)

**Lambda execution role**

![Step 29](LAB_1(image)/step_29.png)

**Developer role assume role permission attached**

![Step 30.2](LAB_1(image)/step_30.2.png)

**Temporary credentials obtained via STS**

![Step 30](LAB_1(image)/step_30.png)

**Access key created and confirmed safe from Git**

![Step 31](LAB_1(image)/step_31.png)

**Final commit and configs/lab-01.env saved**

![Step 33](LAB_1(image)/step_33.png)

**verify-lab-01.sh, final end to end verification**

![Step 34](LAB_1(image)/step_34.png)

### 5.3 Your Turn Practice Tasks

These were small extra tasks placed through the lab to practice a specific command or idea.

**Step 12, aws configure list, checking where each config value comes from**

![Step 12 Your Turn](LAB_1(image)/step_12(turn).png)

**Step 17, comparing list roles output formats**

![Step 17 Your Turn](LAB_1(image)/step_17(turn).png)

**Step 19, creating a 4th practice user (usms-intern-01)**

![Step 19 Your Turn](LAB_1(image)/step_19(turn).png)

**Step 24, generating a CLI skeleton for create vpc**

![Step 24 Your Turn](LAB_1(image)/step_24(turn).png)

**Step 32, predicting and testing policy simulator results for the auditor**

![Step 32 Your Turn](LAB_1(image)/step_32(turn).png)

### 5.4 Independent Lab Exercises (Section 9)

**Exercise 1**
Created a new group and user for QA, and attached the existing developer policy to the group instead of the user directly.

![Exercise 1](LAB_1(image)/section_9(1).png)

**Exercise 2**
Wrote a read only policy that lets the reporting service read student transcripts but denies it from ever writing or deleting anything.

![Exercise 2](LAB_1(image)/section_9(2).png)

**Exercise 3**
Built a role for a third party analytics partner that can only be assumed by the auditor user and only lasts 30 minutes per session.

![Exercise 3](LAB_1(image)/section_9(3).png)

**Exercise 4**
Designed a least privilege policy for a backup job that can copy and verify files but cannot delete anything or touch IAM.

![Exercise 4](LAB_1(image)/section_9(4).png)

Exercise 5 was not attempted for this submission due to time.

## 6. Analysis and Discussion

While working with Floci, a few problems came up along the way.

The first problem was with file paths. The project folder was placed inside a subfolder called LAB_1, so every time the guide said to use ~/aws-floci-course, it did not exist on the machine and the command failed. This got fixed by moving the folder up a level and setting a variable for the project path, so the wrong path did not need to be typed by hand again.

Running aws iam get-account-authorization-details also returned an error saying the operation was not supported. After looking into it, this turned out to be something Floci simply does not implement, not a mistake in the setup, so it got documented as a known limitation instead of being forced to work.

Similarly, floci snapshot save failed with an error saying the snapshot API was not available on this Floci version. Instead of getting stuck, the tar command was used to back up the Floci data folder manually, which achieved the same result.

Running the policy simulator showed a permission as denied even though the user should have had it through their group. Since the group and policy setup were confirmed correct, this pointed to Floci not fully checking permissions that come through group membership, and it got noted down for later.

Lastly, creating a role meant to last only 30 minutes was rejected because it fell below the 1 hour minimum AWS allows for that setting. This got solved by setting the role's maximum to 1 hour and limiting the actual session length to 30 minutes at the point of calling assume role, which is a separate setting.

Working through these issues made the difference between a genuine mistake and a real limit of the tool much clearer.

## 7. Reflection

This lab taught me the basic building blocks of IAM. Users, groups, roles, and policies, and how they connect. The biggest thing I learned is that permissions should go on groups, not directly on users, so it is easier to manage as a team grows.

I also learned that a role needs two separate things to actually work. A trust policy for who can become this role, and a permissions policy for what the role can do. Missing either one breaks it, even though they look similar.

## 8. Conclusion

The objectives of this lab were completed. IAM users, groups, roles, and policies were created using the AWS CLI, and everything was verified using a final verification script. This lab gave a clearer understanding of how IAM is used to manage access in AWS.

## 9. Appendix

### Additional Files
- `docker-compose.yml`
- `configs/course.env`
- `configs/lab-01.env`
- `policies/usms-developer-base-policy.json`
- `policies/usms-student-data-rw-policy.json`
- `policies/usms-self-manage-credentials.json`
- `policies/trust-ec2.json`
- `policies/trust-lambda.json`
- `policies/trust-account-developers.json`
- `policies/usms-reporting-readonly-policy.json`
- `policies/trust-analytics-partner.json`
- `policies/usms-analytics-partner-permissions.json`
- `policies/trust-backup-operator.json`
- `policies/usms-backup-operator-policy.json`
- `scripts/setup/floci-up.sh`
- `scripts/setup/floci-down.sh`
- `scripts/utilities/whoami.sh`
- `scripts/utilities/floci-storage-check.sh`
- `scripts/utilities/verify-lab-01.sh`
- `notes/lab-01-notes.md`
- `labs/lab-01-iam/exercises.md`
- `labs/lab-01-iam/README.md`
