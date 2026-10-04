# AWS Practical Laboratory Report

**Course:** DSO303
**Practical:** Lab 03 — Amazon EC2 and Deploying the USMS Application
**Environment:** Floci (local AWS emulator) via Docker Compose, AWS CLI v2
**Builds on:** Lab 01 (IAM) and Lab 02 (VPC and Networking)

---

## 1. Aim / Objective

The objective of this practical is to deploy a two-tier compute architecture on AWS EC2 for the University Student Management System (USMS) project, reusing the identity foundation built in Lab 01 and the network built in Lab 02. Students will launch a web-tier and a data-tier instance, attach persistent storage, assign a stable public address, create a machine image, and verify that every layer of the resulting system, from IAM permissions down to network reachability, is wired the way it is intended to be.

## 2. Introduction

Amazon EC2 (Elastic Compute Cloud) is the core compute service of AWS, allowing users to launch virtual servers called instances from a chosen machine image and instance type. An instance only becomes useful once it is combined with the surrounding infrastructure: a subnet to sit in, a security group to control its traffic, an IAM instance profile to grant it permissions, storage to hold its data, and in many cases a stable address so that other systems can find it.

This practical is the point in the course where the identity foundation from Lab 01 and the network foundation from Lab 02 are brought together for the first time. A single instance launch in this lab consumes an instance profile created in Lab 01, a subnet and a security group created in Lab 02, and a key pair and a bootstrap script created in this lab itself. The result is a running system rather than a collection of separate exercises.

### Key Features Covered

* EC2 instance lifecycle: launch, describe, stop, start, terminate
* IAM instance profiles and the permission chain from instance to policy
* User data and the cloud-init bootstrap process
* Elastic IP addresses and their difference from auto-assigned public addresses
* EBS volumes, attachment, and the Availability Zone constraint
* Amazon Machine Images (AMIs) and the golden-image pattern
* Security group and network ACL enforcement across a two-tier architecture

## 3. Use Case

The University Student Management System (USMS) is a web application that needs to be reachable by students from the public internet while keeping student records isolated from direct access. A single flat network with one publicly reachable server holding both the application and the database would leave the data tier exposed to anyone who could reach the web tier.

To avoid this, the USMS deployment is split into two tiers:

| Tier | Instance | Subnet | Reachability |
|---|---|---|---|
| Web | usms-web-01 | usms-public-subnet-a | Public, via a stable Elastic IP |
| Data | usms-db-01 | usms-private-subnet-a | Private, no public address, no route to the internet |

The web tier is the only component exposed to students, and it is the only component that carries an IAM instance profile, since it is the only one that will eventually need to write transcripts to S3 in Lab 04. The data tier accepts traffic on port 5432 only from the web tier's own security group, never from an IP range, so that the rule stays correct even if the web tier's address changes.

## 4. System Architecture

The diagram below shows the target two-tier layout: the web instance in the public subnet reachable through the internet gateway and an Elastic IP, and the database instance in the private subnet reachable only from the web tier and only outbound through the NAT gateway.

![Lab 03 Architecture](LAB_03(image)/architecture-1.png)

The second diagram shows the same layout annotated with the actual configuration values used for this deployment, including the security group rules, the IAM profile chain, and the storage attached to each instance.

![Lab 03 Architecture Detail](LAB_03(image)/architecture-2.png)

*(Save the two architecture diagrams into the LAB_03(image) folder as `architecture-1.png` and `architecture-2.png` so the paths above resolve correctly.)*

## 5. Implementation Procedure

The practical began with resuming the Floci environment and sourcing the configuration files produced by Lab 01 and Lab 02, followed by a re-verification of the Lab 02 network to confirm nothing had drifted since the previous session. An Amazon Linux AMI was selected programmatically from the available image catalogue rather than hard-coded, and an EC2 key pair was created with its private key redirected straight to a file and never displayed on screen, then confirmed to be excluded from version control.

A user-data bootstrap script was written to install nginx and publish a small identity page on first boot, and a `run-instances` request was assembled first as a generated skeleton and then as a filled JSON document, combining the public subnet and security group from Lab 02 with the instance profile from Lab 01. The web instance was launched from this document, and its configuration was read back and traced end to end, from the instance to its IAM profile, to its role, to the specific policy attached to that role. A stable Elastic IP was then allocated and associated with the instance so that its public address would not change on a stop and start cycle, and the running configuration was tested both directly and, where the request could not succeed, through a six-point configuration audit covering routing, gateways, security groups, and network ACLs.

An eight gibibyte data volume was created in the same Availability Zone as the web instance and attached separately from the root volume, so that student data would survive an instance termination even though the root volume would not. A second instance was then launched into the private subnet to serve as the database tier, deliberately without a public address and without an instance profile, and the security group rule intended to restrict database access to the web tier alone was inspected and traced. The environment was then paused and resumed to confirm that every resource created in this lab was still present afterwards, an attempt was made to create a golden AMI from the configured web instance, and the full set of resources created in the lab was audited, recorded into a lab-specific environment file, and committed to version control. A verification script was written to check every claim made in this report automatically, and a cleanup script was written and syntax-checked, but deliberately never executed, since later labs depend on the resources this lab produces.

Beyond the core steps, five independent exercises were completed: launching a maintenance instance into the second public subnet, writing an idempotent bootstrap script for a second database instance, writing a reachability-classification script that works from any directory, producing a written cost and right-sizing analysis together with cleanup of the practice resources, and preparing the EC2 side of the S3 hand-off that the next laboratory depends on.

## 6. Results and Evidence

### 6.1 Environment Setup and Network Verification

Before any new resource was created, the environment from the previous two labs was resumed and confirmed intact. All six values needed from Lab 01 and Lab 02, the two subnets, the two security groups, the instance profile, and the Availability Zone, were non-empty and correctly loaded.

![Step 1 - Environment loaded](LAB_03(image)/step1.png)

The Lab 02 network was then re-verified before building on top of it.

![Step 2 - Lab 02 verification](LAB_03(image)/step2.png)

### 6.2 AMI Selection and Key Pair Creation

An Amazon Linux AMI was located through `describe-images` rather than being hard-coded, which is the correct habit even though this practical is running against a local emulator rather than a real AWS region.

![Step 3 - AMI selection](LAB_03(image)/step3.png)


An EC2 key pair was then created, with the private key redirected directly to a file so that it never appeared in the terminal.

![Step 4 - Key pair creation](LAB_03(image)/step4.png)

The private key file was confirmed to be excluded from version control using `git check-ignore`, which names the exact rule responsible.

![Step 5 - Private key git-ignore proof](LAB_03(image)/step5.png)

### 6.3 Bootstrap Script and Launch Request

A user-data bootstrap script was written and checked for syntax errors before being used anywhere.

![Step 6 - user-data.sh syntax check](LAB_03(image)/step6.png)

The full `run-instances` request was then assembled as a JSON document and validated before submission.

![Step 7 - run-instances JSON validated](LAB_03(image)/step7.png)

### 6.4 Web Tier Launch

The web tier instance was launched successfully, combining the subnet and security group from Lab 02 with the instance profile from Lab 01.

![Step 8 - usms-web-01 launched](LAB_03(image)/step8.png)

The instance was then waited on until it reached the running state.

![Step 9 - waiter exit code](LAB_03(image)/step9.png)

The instance's full configuration was read back to confirm that every field, subnet, security group, key pair, and instance profile, matched what had been requested.

![Step 10 - Instance configuration table](LAB_03(image)/step10.png)

### 6.5 Permission Chain and User Data

The permission chain was traced from the instance to its instance profile, to its role, and finally to the specific IAM policy attached to that role.

![Step 11 - Permission chain trace](LAB_03(image)/step11.png)

An attempt was made to prove that the user data stored by the platform matched the script written locally, byte for byte.

![Step 12 - User data verification attempt](LAB_03(image)/step12.png)

### 6.6 Elastic IP Assignment

A stable Elastic IP address was allocated and associated with the web instance so that its public address would not change if the instance were ever stopped and started again.

![Step 13 - Elastic IP allocation](LAB_03(image)/step13.png)

While confirming this, an inconsistency in the underlying platform's address handling was discovered and is documented in full in Section 7.

![Step 13 - Address handling limitation](LAB_03(image)/step13(limitation).png)

### 6.7 Reachability Testing

A direct request to the application was attempted and, as expected for this environment, timed out. In place of a successful request, every configuration property that would have made the request succeed on a real deployment was checked and confirmed independently. This process also uncovered a genuine misconfiguration, a network ACL association that was corrected before continuing.

![Step 14 - Reachability check and NACL correction](LAB_03(image)/step14.png)

### 6.8 Data Volume

A separate eight gibibyte data volume was created in the same Availability Zone as the web instance and attached to it, distinct from the root volume so that it would survive an instance termination.

![Step 15 - Data volume created and attached](LAB_03(image)/step15.png)

### 6.9 Database Tier Launch

The database tier instance was launched into the private subnet, deliberately without a public address and without an instance profile, since it has no need to reach the internet or call any AWS service directly.

![Step 16 - usms-db-01 launched](LAB_03(image)/step16.png)

### 6.10 Two-Tier Wiring Verification

The wiring between the two tiers was checked: which security group each instance carries, what the database security group actually admits, and whether the private subnet has any route to the internet.

![Step 17 - Two-tier wiring check](LAB_03(image)/step17.png)

### 6.11 Stop and Start Behaviour

The web instance was stopped and started again to observe which address changes and which does not across the cycle.

![Step 18 - Stop and start cycle](LAB_03(image)/step18.png)

### 6.12 Persistence After Restart

The entire Floci environment was paused and resumed to confirm that every instance, subnet association, and security group assignment created in this lab survived the cycle.

![Step 19 - Persistence proof](LAB_03(image)/step19.png)

### 6.13 Golden AMI Attempt

An attempt was made to create a golden AMI from the configured web instance, for use in a later laboratory's Auto Scaling group. This operation was not supported by the platform, and the finding is discussed in Section 7.

![Step 20 - create-image error](LAB_03(image)/step20(error).png)

### 6.14 Resource Audit

Every instance, volume, Elastic IP, and image created by this lab was audited in a single pass before recording the final environment file.

![Step 21 - Full resource audit](LAB_03(image)/step21.png)

### 6.15 Environment File and Version Control

The lab's environment file was generated by looking every resource up by tag rather than by remembered shell variables, and confirmed to have every value populated.

![Step 22 - lab-03.env populated](LAB_03(image)/step22.png)

The lab's files were then committed to version control, after confirming that nothing sensitive was staged.

![Step 23 - Commit](LAB_03(image)/step23.png)

### 6.16 Final Verification

A verification script covering every claim made in this report was written and run, producing a final tally with a small number of failures, each one fully explained in Section 7.

![Step 24 - Final verification run](LAB_03(image)/step24.png)

### 6.17 Cleanup Script

A teardown script for this lab's resources was written and checked for syntax correctness, but deliberately never executed, since Lab 04 depends on the web instance created here still being present.

![Step 25 - Cleanup script syntax check](LAB_03(image)/step25.png)

### 6.18 Independent Exercises

**Exercise 1 — Maintenance instance.** A second instance was launched into the other public subnet without an instance profile, tagged as an ephemeral administrative host, and confirmed to be the only instance in that Availability Zone carrying the administrative tier tag.

![Exercise 1 - Maintenance instance verification](LAB_03(image)/ex1.png)

**Exercise 2 — Self-describing database bootstrap.** An idempotent bootstrap script was written for the database tier, guarded by a marker file so that a second execution would exit immediately rather than repeating its work, and applied to a second database instance in the other Availability Zone.

![Exercise 2 - Script and instance launch](LAB_03(image)/ex2.1.png)

![Exercise 2 - Second launch](LAB_03(image)/ex2.2.png)

The byte-for-byte comparison between the script written locally and the data returned by the platform did not match, consistent with the same limitation observed in Section 6.5, and is explained fully in Section 7.

![Exercise 2 - Byte comparison result](LAB_03(image)/ex2.mismatch.png)

**Exercise 3 — Reachability report.** A script was written to classify every USMS instance as reachable, unreachable, or without an address, based only on route table and security group data, and was confirmed to produce identical output regardless of which directory it was run from.

![Exercise 3 - Run from repository directory](LAB_03(image)/ex3.1dir.png)

![Exercise 3 - Run from home directory](LAB_03(image)/ex3.2dir.png)

**Exercise 4 — Right-sizing and cleanup.** An attempt was made to check the web instance's CPU credit mode as part of a cost and scaling analysis, which was not supported by the platform.

![Exercise 4 - Credit specification attempt](LAB_03(image)/ex4.1.png)

The maintenance instance from Exercise 1 was then terminated as part of the cleanup, and the lab's verification script was re-run afterwards to confirm nothing else had been disturbed.

![Exercise 4 - Cleanup and re-verification](LAB_03(image)/ex4.2.png)

**Exercise 5 — S3 hand-off preparation.** A script was written to allow the web instance to upload student transcripts to S3 using its instance profile alone, with no access keys of any kind referenced in the script.

![Exercise 5 - Upload script](LAB_03(image)/ex5.1.png)

The outbound rule that makes the S3 call possible without any additional firewall change was confirmed.

![Exercise 5 - Outbound rule confirmation](LAB_03(image)/ex5.2.png)

Finally, a readiness file was produced summarising the full permission chain and confirming that the destination bucket does not yet exist, which is exactly the state the next laboratory expects to find.

![Exercise 5 - S3 readiness file](LAB_03(image)/ex5.3.png)

## 7. Analysis and Discussion

The practical succeeded in producing a correctly configured two-tier architecture. The web instance carries the intended security group and instance profile and sits in the intended public subnet, and the database instance carries its own security group and sits in the intended private subnet with no public address and no permissions it does not need. The route tables correctly separate the two tiers, with the private subnet routing outbound traffic only through the NAT gateway and having no path at all to the internet gateway. The final verification script, covering thirty six separate checks, passed thirty three of them, and every one of the three remaining failures traces back to a specific, reproducible limitation of the Floci emulator rather than to a mistake in configuration, each of which is described below.

The first limitation concerns security group rules that reference another security group rather than an IP address range. The database security group was configured to admit PostgreSQL traffic only from the web tier's own security group, and the API call to create this rule reported success and returned a real rule identifier. Reading the security group back afterwards, however, showed the rule was never actually stored. This was confirmed by attempting the same call several times and inspecting the group directly rather than trusting the API's success response, and the duplicate rules this produced were cleaned up afterwards.

The second limitation concerns the address fields returned for every instance in this environment. Both the web and the database instance returned implausible values for their private and public addresses, values that did not belong to the configured VPC's address range at all, rather than the correct value or an empty field. This was verified to be consistent across every instance launched during the practical, including instances created purely for testing, and does not appear to depend on subnet type or launch method.

The third limitation involves the relationship between an Elastic IP and the instance it is associated with. Associating an address with the web instance was reported as successful, and looking the address up directly confirmed the association was recorded correctly. Looking the instance up instead, however, continued to show its earlier, incorrect public address rather than the newly associated one. The two sides of the same relationship gave two different answers depending on which resource was queried.

The fourth limitation is that user data supplied at launch time is never returned by the platform afterwards. This was tested three separate times, once against the web instance with its full bootstrap script, once against a disposable instance carrying a single line of test data, and once against the second database instance created during the independent exercises, and in every case the platform reported no user data at all rather than returning an incorrect or partial value.

The fifth limitation is different in character from the first four. Creating a machine image from the running web instance was rejected outright by the platform as an unsupported operation, and the same result was obtained even with a minimal request containing none of the original tags or description. Unlike the earlier limitations, where the platform accepted a request and then failed to store or return the result correctly, this was a case of a feature not being implemented at all, and the same behaviour was later observed for a second, unrelated operation used during the cost analysis in Exercise 4.

Two further findings were made during this practical that were not platform limitations but genuine issues that needed to be corrected. While investigating why the deployed application could not be reached, the public subnet was discovered to be associated with the restrictive network access control list built in Lab 02 for the private tier, rather than with the account's default, permissive list. This meant that inbound web traffic would have been denied by the network ACL even before reaching the security group, which is a real and independent reason for the application being unreachable, separate from the emulator's inability to boot an operating system. This was corrected by re-associating the public subnet with the default network ACL. Separately, the lab's own verification script was found to contain two logic errors of its own, one that treated the intentionally tracked `.gitkeep` placeholder file as a leaked secret, and one that reported the missing golden AMI and the missing user data as present because of how the underlying shell test handled an empty or literal "None" result. Both were corrected so that the verification script's output would accurately reflect the environment rather than hide genuine gaps behind an accidental pass.

## 8. Reflection

This practical was the point in the course where the separate pieces built in earlier labs finally combined into something that behaves like real infrastructure rather than a set of isolated exercises. Watching a single launch command reach back into an IAM profile from one lab and a subnet from another was a clearer demonstration of how cloud deployments actually fit together than any of the individual identity or networking exercises had been on their own.

The most valuable part of the practical, however, turned out to be the troubleshooting rather than the happy path. Several times during this lab, a command appeared to succeed and returned exactly the response the documentation predicted, and yet the underlying resource had not actually been configured the way the response implied. Learning to treat a successful response as a claim to be checked, rather than as proof in itself, was the single most useful habit this practical reinforced, and it is a habit that applies well beyond this specific emulator.

I also found it useful to distinguish between the two very different kinds of limitation encountered in this lab. Some operations were accepted by the platform and then silently failed to persist correctly, which required comparing what was written against what was later read back. Others were rejected outright as unsupported, which required no such comparison but did require ruling out that the rejection was specific to how the command had been written before accepting it as a genuine platform gap. Recognising which kind of problem I was looking at each time shaped how I investigated it.

In future practicals, I would like to explore how a real AWS account handles the operations that could not be completed here, particularly the creation of a machine image and the behaviour of burstable instance credits under sustained load, both of which this practical could only reason about rather than observe directly.

## 9. Conclusion

The objectives of this practical were achieved. A two-tier EC2 architecture was successfully deployed for the USMS project, combining the identity foundation from Lab 01 with the network foundation from Lab 02, and every claim about that architecture, its subnet placement, its security groups, its storage, and its permission chain, was independently verified rather than assumed. Where the underlying emulator could not fully support a requested operation, the gap was isolated, confirmed through repeated and varied testing, and documented rather than worked around, and one genuine network misconfiguration was found and corrected in the process. This laboratory reinforced that a cloud deployment is only as trustworthy as the verification performed against it, and that a successful command is the beginning of that verification, not the end of it.

## 10. Appendix

### Additional Files

* `labs/lab-03-ec2/user-data.sh`
* `labs/lab-03-ec2/user-data-db.sh`
* `labs/lab-03-ec2/transcript-upload.sh`
* `templates/lab-03-run-instances.json`
* `configs/lab-03.env`
* `scripts/utilities/verify-lab-03.sh`
* `scripts/utilities/lab-03-reachability.sh`
* `scripts/cleanup/lab-03-cleanup.sh`
* `outputs/lab-03-s3-readiness.txt`
* `labs/lab-03-ec2/exercises.md`
* `notes/lab-03-notes.md`

### Submission Checklist

* Student information completed
* Objectives stated
* Introduction provided
* Real-world use case described
* System architecture included
* Implementation documented
* CLI outputs included for all lab steps
* CLI outputs included for all five independent exercises
* Platform limitations identified and documented
* Genuine configuration issues identified and corrected
* Analysis completed
* Reflection completed
* Conclusion written