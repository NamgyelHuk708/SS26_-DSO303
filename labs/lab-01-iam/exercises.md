# Lab 1 Independent Exercises Report
## Exercise 1: The QA Identity

**Requirement:** Create a group called usms-qa and a user called usms-qa-01 inside it. Attach the existing USMSDeveloperBase policy to the group, not to the user directly.

**What was done:**
A new group usms-qa was created, and a new user usms-qa-01 was created and tagged with Role QA and Project USMS. The user was added to the group, and the existing USMSDeveloperBase policy was attached to the group only.

**Verification:**
Checking the group showed usms-qa-01 as a member of usms-qa. The attached group policies showed USMSDeveloperBase attached to the group. The attached user policies for usms-qa-01 came back empty, which confirmed nothing was attached directly to the user.

![Exercise 1](LAB_1(image)/section_9(1).png)

---

## Exercise 2: The Read Only Reporting Policy

**Requirement:** Write a policy called USMSReportingReadOnly that lets a reporting service list the student data bucket and read only files under the transcripts folder, while explicitly denying every write and delete action on that bucket.

**What was done:**
A policy file was written with three parts. The first part allows listing the bucket. The second part allows reading objects only under the transcripts folder. The third part explicitly denies all write and delete actions on both the bucket and its objects. The file was checked locally to make sure the JSON was valid before it was uploaded as a customer managed policy named USMSReportingReadOnly.

**Verification:**
Listing local policies showed USMSReportingReadOnly with a valid ARN and a default version of v1.

![Exercise 2](LAB_1(image)/section_9(2).png)

---

## Exercise 3: The Third Party Analytics Role

**Requirement:** Build a role that a partner university can assume to read reports for at most 30 minutes, without having their own IAM user in the account.

**What was done:**
A trust policy was written so that only usms-audit-01 can assume the role. A separate permissions policy was written to allow reading objects only under the reports folder. The role was tagged with Project USMS and External true.

One problem came up while setting this up. AWS does not allow a role's maximum session length to go below one hour, even though the task asked for 30 minutes. This was solved by setting the role's maximum session length to one hour, the smallest value AWS allows, and then asking for a shorter session of 30 minutes when actually calling assume role. The role's own maximum only sets the upper limit, and a shorter session can still be requested at the time of assuming it.

**Verification:**
Checking the role confirmed the maximum session length was set to 3600 seconds and that only usms-audit-01 was trusted to assume it. Calling assume role with a session length of 1800 seconds returned an expiration time about 30 minutes ahead, which met the real requirement.

**On external id:**
If this partner were a real outside AWS account instead of a user inside this same account, an external id should be added to the trust policy. This stops a situation where another company's own systems could be tricked into assuming this role by mistake. It was not added here since the partner in this exercise is just another user already inside the same account.

![Exercise 3](LAB_1(image)/section_9(3).png)

![Exercise 3 assume role result](LAB_1(image)/section_9(3.1).png)

---

## Exercise 4: Least Privilege Backup Operator Policy

**Requirement:** Design a policy for a nightly backup job that copies files from the student data bucket into an archive bucket, checks what it copied, and writes a log line, without ever deleting anything or touching IAM, and only in us-east-1.

**Decision: a role, not a user.**
Since this job runs on its own overnight with no person involved, a role made more sense than a user. A role gives temporary credentials that refresh on their own, so there is no long term secret sitting anywhere, which matches the same reasoning used earlier for the EC2 application role.

**What was done:**
A trust policy was written so the EC2 service can assume the role. A permissions policy was written with three parts. The first part allows reading and listing the source bucket. The second part allows writing to the archive bucket and reading from it, since checking a copy means reading the file back after it was written. The third part allows writing a single log line to one specific log group. Both S3 parts include a rule that limits everything to the us-east-1 region.

There is no single action in AWS for copying a file directly. A copy is really just reading the file from one place and writing it to another, which is why two separate permissions were needed instead of one copy action.

**Three ways this policy could still be misused, and how each one could be fixed:**

The job could overwrite an archive file with something broken or unexpected, since there is no check on file size or type. Turning on versioning on the archive bucket would keep older copies safe even if this happened.

There is no rule that blocks delete actions outright. Even though delete was never given, a future change to the policy could add it by accident. Adding a clear denial of delete actions would protect against that no matter what changes later.

The role has no limit on how long a session can last. If the credentials ever leaked, they could stay usable for a long time. Setting a maximum session length, similar to the developer role, would limit how long leaked credentials could actually be used.

![Exercise 4](LAB_1(image)/section_9(4).png)

---

## Exercise 5: Preparing the Developer Policy for Lab 2

**Requirement:** Check whether the developer policy already covers every EC2 action Lab 2 will need, add only the missing actions as a new policy version, and prepare a VPC address range for Lab 2 to use.

**What was done:**
The current policy version, version 2, was checked against the full list of actions Lab 2 needs. Two actions were missing, one for creating a NAT gateway and one for allocating an address. A NAT gateway needs its own address, which is why the second action was needed alongside the first.

A new version of the policy was created with only those two actions added and nothing else changed. This was uploaded as version 3 and set as the new default.

The lab config file was also updated with a new value for the VPC address range, so Lab 2 can read it later.

Since the verification script originally checked that the default version was v2, that check was updated to expect v3 instead, so the script still matches reality.

**Verification:**
Listing the policy versions showed v1 and v2 marked as not default, and v3 marked as the new default, which confirmed the update worked without removing any earlier version.

![Exercise 5](LAB_1(image)/section_9(5).png)

---

## Summary

All five exercises were finished. Exercise 5 was completed after being skipped at first, then finished before submission. These exercises gave practice in writing tight policies by hand, choosing between a user and a role depending on the situation, working around a real AWS limit that did not match what the task asked for, and updating an existing policy safely without breaking anything that depended on it.