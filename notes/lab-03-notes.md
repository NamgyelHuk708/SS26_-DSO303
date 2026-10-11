# Lab 03 Notes — Review Questions

---

## Q1. What if one of the five launch inputs was wrong or missing?

| Input | If wrong (e.g. ID doesn't exist) | If missing or wrong-but-valid |
|---|---|---|
| Subnet (Lab 2) | **Immediate:** `InvalidSubnetID.NotFound`, or `MissingParameter` if the variable was empty | **Silent:** launching into the private subnet by mistake succeeds, but the instance gets no public IP and is unreachable |
| Security group (Lab 2) | **Immediate:** `InvalidGroup.NotFound` | **Silent:** if omitted, the VPC's default SG is attached, which allows nothing on port 80, so the site is unreachable with no error |
| Instance profile (Lab 1) | **Immediate:** `InvalidParameterValue: iamInstanceProfile.name` | **Silent:** if omitted, the instance launches fine and only fails much later, when the app calls S3 and finds no credentials |
| Key pair (Lab 3) | **Immediate:** `InvalidKeyPair.NotFound` | **Silent:** if omitted, the instance runs but nobody can ever SSH into it, and a key cannot simply be added afterwards |
| User-data script (Lab 3) | Never immediate. A broken script is accepted, because EC2 only stores it | **Silent:** the error happens at boot, inside the instance, and is only visible in `/var/log/usms-bootstrap.log`. That is why `bash -n` was run first |

The pattern is that a wrong ID fails loudly at launch, but a missing or wrong-but-valid choice almost always fails silently later, which is much worse.

---

## Q2. Why is a policy for a bucket that doesn't exist valid?

An IAM policy is a statement about **ARNs**, not a link to real objects. `USMSStudentDataReadWrite` says that whoever holds it may read and write anything at `arn:aws:s3:::usms-student-data`. IAM does not check whether anything exists at that ARN, so the policy is perfectly valid. Today it simply has nothing to apply to. If `usms-web-01` tried to upload now, it would not get `AccessDenied`; it would get a "bucket not found" error, which is exactly the `404 Not Found` the `head-bucket` check returned in Exercise 5. The moment the bucket is created (the lab says Lab 4, but the updated course creates it in Lab 10), the policy starts working instantly. No change is needed to the policy, the role, the instance profile or the instance, and there is still no access key anywhere on the machine. The same thing will be true for the ECS task role in Lab 04, which reuses this exact policy.

---

## Q3. Why can't user data be used to "redeploy on restart"?

User data runs **once**, on the very first boot, through cloud-init. Rebooting, or stopping and starting the instance, does **not** run it again. So putting the deployment in user data only deploys the version that existed on launch day, and restarting the instance redeploys nothing.

Two approaches that do work:

1. **Immutable deployment.** Build a new AMI (or container image) for each release, then replace the old instances with new ones, for example with a launch template and an Auto Scaling group "instance refresh". Every new instance boots with the new version already inside.
2. **A deployment tool that runs on demand.** Use AWS CodeDeploy, SSM Run Command, or a systemd service that pulls the latest release on every boot. The deployment then happens whenever you trigger it, not only at first boot.

Running the app as containers on ECS (Lab 04) is a third option. A new task definition revision replaces running tasks without touching any server.

---

## Q4. Auto-assigned public IP vs Elastic IP

| | Auto-assigned public IP (Step 10) | Elastic IP (Step 13) |
|---|---|---|
| Who owns it | AWS. It is lent to the instance from a shared pool | **My account.** It stays mine until I release it |
| When it changes | Every stop/start gives a new address | Never, until I release it |
| Cost | Since February 2024, AWS charges about $0.005/hour for every public IPv4 address | Also about $0.005/hour, **including** while it is not attached to a running instance (about $3.60/month idle) |
| On stop | Released immediately and lost | Stays allocated, and stays associated with the instance |

In my Floci run, the stopped instance kept showing `127.0.0.1` instead of losing its public address, so I could not observe the release. On real AWS it would show `None` while stopped.

**Failover that needs an Elastic IP:** if `usms-web-01` fails, the Elastic IP can be moved to a standby instance (for example `usms-web-02` in the other AZ) with `associate-address --allow-reassociation`. The DNS record for the portal points at the Elastic IP, so it does not change, and students reach the new server within seconds. With an auto-assigned IP this is impossible, because the address dies with the instance.

---

## Q5. Why can a snapshot cross AZs when a volume cannot?

An EBS **volume** is stored inside one Availability Zone's storage system, close to the servers that use it, which is why it can only attach to instances in that same AZ. A **snapshot** is stored in S3, which is regional and keeps copies across several AZs. So a snapshot can be restored as a new volume in any AZ in the region.

For a system that must survive losing one AZ, this means:

- Data on a single volume (like `usms-web-data-vol` in `us-east-1a`) is lost or unavailable if that AZ goes down
- Regular, automatic snapshots (for example with Data Lifecycle Manager) are needed so the data can be rebuilt in another AZ
- For real availability rather than just recovery, data should be replicated across AZs while running, for example with RDS Multi-AZ (planned later in the course) or replication at the application level

---

## Q6. Are the six configuration checks a good substitute for a real request?

They are a good substitute for **proving the AWS configuration is right**, but not for proving the application works. All six checks passed in my run, and checking them also caught a real fault: the public subnet was wrongly using `usms-private-nacl`, which would have blocked web traffic on real AWS.

The class of fault they **cannot** detect is anything **inside the instance**, which is the seventh link in the chain. That includes:

- nginx not installed or crashed
- the user-data script failing at boot
- an OS-level firewall blocking port 80
- an application bug

The checks also only read the configuration. They don't prove AWS enforces it, and Floci does not enforce security groups at all. So they show the path is open, not that anything is listening at the end of it.

---

## Q7. Every difference between `usms-web-01` and `usms-db-01`

| Difference | `usms-web-01` | `usms-db-01` | Property of |
|---|---|---|---|
| Subnet chosen at launch | `usms-public-subnet-a` | `usms-private-subnet-a` | **Instance** (chosen at launch) |
| Private IP range | `10.0.1.0/24` | `10.0.3.0/24` | **Subnet** (its CIDR) |
| Gets a public IP at launch | Yes | No | **Subnet** (`MapPublicIpOnLaunch`) |
| Elastic IP | `usms-web-eip` | None | **Instance** (an association with an account resource) |
| Route to the internet | Via `usms-igw` (inbound + outbound) | Via `usms-nat` (outbound only) | **Subnet** (its route table) |
| Network ACL | Default NACL (after my fix) | `usms-private-nacl` | **Subnet** |
| Security group | `usms-app-sg` (80/443 from anywhere) | `usms-db-sg` (5432 from app tier only) | **Instance** (its network interface) |
| Instance profile | `usms-ec2-app-profile` | None | **Instance** |
| User data | Web bootstrap script | None | **Instance** |
| Extra data volume | `usms-web-data-vol` | None | **Instance** |
| Name / Tier tags | `web` | `data` | **Instance** |

What they **share** comes from the **VPC**: the `10.0.0.0/16` range, DNS support and hostnames, the attached internet gateway, and the fact that they can talk to each other through the `local` route. They also share the same AZ (`us-east-1a`), but that comes from their subnets, not from the VPC.

Note: Floci reported `127.0.0.1` as the public address for both instances, so the "public IP" row is based on the subnet settings, not on what Floci displayed.