# AWS Practical Laboratory Report

## Lab 2 Building a Secure VPC with AWS CLI

### 1. Aim / Objective

This practical covers how Amazon VPC is used to build an isolated, multi-tier network in AWS. It also covers controlling access to that network through IAM role assumption, security groups, and network ACLs. All work was done using the AWS CLI in the Floci learning environment, following the same command-line approach as Lab 1.

### 2. Introduction

Amazon VPC is a regional networking service that lets an account create its own private section of the AWS cloud. It comes with its own IP range, subnets, route tables, and gateways. Nothing inside a VPC can reach the internet, or anything else, unless a route, a gateway, and a firewall rule all allow it. This makes VPC one of the core building blocks of AWS security, alongside IAM.

**Key Features**

- Custom IP addressing (CIDR blocks) and subnetting across multiple Availability Zones
- Route tables that control where traffic from a subnet can go
- Internet Gateways for public traffic and NAT Gateways for private-subnet traffic that still needs outbound access
- Security Groups — stateful, instance-level firewalls
- Network ACLs — stateless, subnet-level firewalls that act as a second layer of defence
- VPC Endpoints, which let private resources reach services like S3 without using the internet
- Resource tagging for organisation and automation

### 3. Use Case

Consider a small organisation, USMS, running a three-tier application: a web/application tier the public needs to reach, and a database tier that must stay hidden. A typical network design splits it like this:

| Tier | Subnet Type | Access |
|---|---|---|
| Application (web) | Public | HTTP/HTTPS from the internet; SSH only from inside the VPC |
| Application (internal) | Private | No inbound from the internet; outbound access only through a NAT Gateway |
| Database | Private (isolated) | PostgreSQL, allowed only from the application tier's security group, never from a raw IP range |

This is the layout built in this lab: a public subnet for internet-facing resources, a private subnet for the application layer, and security groups that reference each other by group ID instead of by CIDR block. This keeps the database tier reachable only through the application tier.

### 4. System Architecture / Design

The diagram below shows the layout of usms-vpc (10.0.0.0/16). It has one public subnet and one private subnet in the same Availability Zone, plus a second public subnet in another Availability Zone for redundancy.

The public subnet routes to the Internet Gateway and hosts the NAT Gateway. The private subnet has no route to the Internet Gateway — it reaches the internet only through the NAT Gateway. This is what makes it private, not its name or tags.

Two security groups control access. usms-app-sg allows HTTP and HTTPS from the internet, and SSH only from inside the VPC. usms-db-sg allows PostgreSQL only from usms-app-sg's group ID, not from a CIDR range, so only the app tier can reach the database.

A custom NACL, usms-private-nacl, is attached to the private subnet as a second layer of defence behind the security groups.

| Route Table | Destination | Target |
|---|---|---|
| Public Route Table | `10.0.0.0/16` | local |
| Public Route Table | `0.0.0.0/0` | Internet Gateway |
| Private Route Table | `10.0.0.0/16` | local |
| Private Route Table | `0.0.0.0/0` | NAT Gateway |

An S3 Gateway VPC Endpoint is attached to the private route table, so traffic to S3 stays inside the AWS network instead of going out through the NAT Gateway.

![alt text](LAB_2(image)/1.png)

Figure 1: VPC architecture across two Availability Zones with public/private subnets and route tables

![alt text](LAB_2(image)/3.png)

Figure 2: Final architecture showing Web Server 1 and the Web Security Group placement


### 5. Implementation Procedure

The practical began with prerequisite checks to confirm Lab 1 was complete and the Floci environment was healthy. A developer role was assumed to create the VPC (usms-vpc, 10.0.0.0/16) with DNS support enabled, an Internet Gateway attached, and identity was then restored to root. A public and a private subnet were created in one Availability Zone, along with a public and private route table — the public route table pointed to the Internet Gateway, while the private route table was left with no default route, which is what actually keeps it private. A second public subnet was added in another Availability Zone for redundancy.

Two security groups were then configured: usms-app-sg, allowing HTTP and HTTPS from the internet and SSH from inside the VPC only, and usms-db-sg, allowing PostgreSQL only from usms-app-sg's group ID rather than a CIDR range. A custom NACL was created and attached to the private subnet as a second layer of defence. A NAT Gateway was then set up in the public subnet, and the private route table's default route was pointed to it, giving the private subnet outbound access without exposing it directly. An S3 Gateway VPC Endpoint was added to the private route table so S3 traffic stays inside the AWS network.

Finally, all resources were verified through tagging, persistence was confirmed across a Floci container restart, resource IDs were saved to configs/lab-02.env, and the work was committed to git. A verification script and a cleanup script (built but not run) closed out the lab. Independent Exercises 1–5 are documented separately in exercises.md.

### 6. Results and Evidence

#### 6.1 CLI Output

This lab was done entirely through the AWS CLI in Floci, so there is no separate console to check. Verification was done through `describe-*` calls after each step, shown below.

**Before You Start prerequisite check**

![alt text](LAB_2(image)/1pre.png)

**Part A Environment and Identity**

Step 1: Floci resume and storage check:

![alt text](LAB_2(image)/step_1.png)

Step 2: identity and Lab 1 variables:

![alt text](LAB_2(image)/step_2.png)

**Part B uilding the Network**

Step 3: assumed role and VPC creation:

![alt text](LAB_2(image)/step_3.png)

Step 4: restored identity and VPC details:

![alt text](LAB_2(image)/step_4.png)

Step 6: Internet Gateway attached:

![alt text](LAB_2(image)/step_6.png)

Step 7: public subnet created:

![alt text](LAB_2(image)/step_7.png)

Step 9: public vs private subnet table:

![alt text](LAB_2(image)/step_9.png)

Step 11: public route table associations:

![alt text](LAB_2(image)/step_11.png)

Step 13: public vs private route-target proof:

![alt text](LAB_2(image)/step_13.png)

**Part C Security Groups and NACL**

Step 14: application security group rules:

![alt text](LAB_2(image)/step_14.png)

Step 15 — database security group sourced from app SG:

![alt text](LAB_2(image)/step_15.png)

Step 16: security group summary:

![alt text](LAB_2(image)/step_16.png)

Step 17: private NACL entries:

![alt text](LAB_2(image)/step_17.png)

Step 18: NACL association swapped:

![alt text](LAB_2(image)/step_18.png)

**Part D NAT Gateway and S3 Endpoint**

Step 19: NAT gateway available:

![alt text](LAB_2(image)/step_19.png)

Step 20: private route table via NAT:

![alt text](LAB_2(image)/step_20.png)

Step 21: S3 VPC endpoint:

![alt text](LAB_2(image)/step_21.png)

**Part E Tagging, Persistence, and Commit**

Step 22: tag audit table:

![alt text](LAB_2(image)/step_22.png)

Step 23: persistence proven:

![alt text](LAB_2(image)/step_23.png)

Step 24: environment file populated:

![alt text](LAB_2(image)/step_24.png)


**Part F Verification and Cleanup**

Step 26: verification script results:

![alt text](LAB_2(image)/step_26.png)

Step 27: cleanup script syntax check:

![alt text](LAB_2(image)/step_27.png)

#### 6.2 AWS Management Console Verification

![alt text](LAB_2(image)/4.png)

Figure 3: Resource map confirming the VPC, subnets, route tables, and network connections were created successfully.

![alt text](LAB_2(image)/5.png)

Figure 4: Subnet list confirming all four subnets exist across both Availability Zones.

![alt text](LAB_2(image)/6.png)

Figure 5: Route table subnet associations updated, confirming lab-rtb-public and lab-rtb-private1-us-east-1a each associated with 2 subnets.

![alt text](LAB_2(image)/7.png) 

Figure 6: Web Security Group created successfully with an inbound rule permitting HTTP access.

![alt text](LAB_2(image)/8.png)

Figure 7: EC2 instance list showing Web Server 1 in the Running state with 2/2 status checks passed.

![alt text](LAB_2(image)/9.png)

Figure 8: Browser confirming the deployed web application, displaying the correct Instance ID, Availability Zone, and live CPU load.
---
### 7. Analysis and Discussion

Most of the lab worked as expected. The VPC, subnets, route tables, security groups, NACL, NAT Gateway, and S3 endpoint were all created and verified, and everything survived a full container restart, confirming Floci's storage is persistent.

A few Floci-specific quirks came up and are worth noting:

- **Security group rule sourced from another group.** When `usms-db-sg`'s PostgreSQL rule referenced `usms-app-sg` instead of a CIDR block, Floci's raw response did not always show that reference cleanly. This looks like a limitation of the emulated environment, not a configuration error, since the intent of the rule was still correctly sent to the API.
- **Tag-based filtering on NACLs.** Filtering NACLs by tag sometimes returned the wrong resource. A broader query with a client-side JMESPath filter (`[?Key=='Name']`) fixed this.
- **`Associations[0]` is not safe to assume.** Once a NACL or route table has more than one association, taking the first array entry can pick the wrong subnet. Filtering by `SubnetId` avoided this.
- **S3 endpoint route visibility.** After attaching the S3 endpoint, `describe-route-tables` did not always show the expected prefix-list route, even though the endpoint itself reported as available. This seems to be a display issue in Floci, not a functional one.

None of these affected the design. Routing still decides public vs. private status, proven independently of tags in Step 13, and the database tier is still reachable only through the application tier's security group.

### 8. Reflection

This practical gave me a clearer picture of how AWS decides whether a subnet is public or private. It has nothing to do with naming or tags, and everything to do with where its route table points.

One key observation was the value of defence in depth: security groups and NACLs cover different layers, and referencing security groups by ID instead of CIDR range removes a whole class of mistakes. Assuming a developer role for resource creation, then dropping back to the root identity right after, reinforced the same least-privilege habit from Lab 1.

In real-world cloud environments, this pattern would be used to isolate sensitive workloads, control traffic between application tiers, and keep private resources unreachable from the internet by design.

In future practical sessions, I would like to learn about:

- VPC Peering and Transit Gateway
- AWS Network Firewall
- Site-to-Site VPN
- Multi-account networking with AWS Resource Access Manager (RAM)
- Cost-optimised NAT strategies for smaller workloads

### 9. Conclusion

The objectives of this practical were achieved. A secure, multi-tier VPC was built using only the AWS CLI, with public and private subnets, gateways, route tables, security groups, a network ACL, and a VPC endpoint. Every design decision was verified rather than assumed. The lab confirmed that in AWS networking, what a route table actually points to is the source of truth, not labels.

### 10. Appendix

**Additional Files**

- `configs/lab-02.env`
- `scripts/utilities/verify-lab-02.sh`
- `scripts/utilities/lab-02-network-report.sh`
- `scripts/cleanup/lab-02-cleanup.sh`
- `policies/usms-db-sg-ingress.json`
- `notes/lab-02-notes.md`
- `exercises.md` (Independent Exercises 1–5, documented separately)

**Submission Checklist**

- [x] Student information completed
- [x] Objectives stated
- [x] Introduction provided
- [x] Real-world use case described
- [x] Tools listed
- [x] System design included *(text description complete; diagram image pending)*
- [x] Implementation documented
- [x] CLI outputs included
- [x] Console screenshots attached *(not applicable — CLI-only environment)*
- [x] Analysis completed
- [x] Reflection completed
- [x] Conclusion written