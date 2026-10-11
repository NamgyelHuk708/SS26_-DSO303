# Lab 3 Independent Exercises

---

## Exercise 1: Maintenance Instance

### What I did
I launched `usms-admin-01-host` as a t3.micro in `usms-public-subnet-b`. I used `usms-app-key` and `usms-app-sg`, and I did not give it an instance profile because an admin host doesn't need to access S3. I used the long command form like in Step 16, not the JSON file.

```bash
ADMIN_INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type t3.micro \
  --key-name usms-app-key \
  --subnet-id "$USMS_PUBLIC_SUBNET_B" \
  --security-group-ids "$USMS_APP_SG" \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=usms-admin-01-host},{Key=Project,Value=USMS},{Key=Tier,Value=admin},{Key=Lab,Value=03},{Key=Ephemeral,Value=true}]' \
  --query 'Instances[0].InstanceId' --output text)

aws ec2 wait instance-running --instance-ids "$ADMIN_INSTANCE_ID"
```

I used the waiter instead of `sleep`, and it returned exit code 0. I did not add this instance to `configs/lab-03.env` since it gets deleted in Exercise 4.

### Verification
Filtering on `Tier=admin` gave exactly one running instance:

- ID: `i-9b5013104c797ef06`
- AZ: `us-east-1b`
- Subnet: `subnet-071924d0` (public subnet b)
- Profile: None

![Exercise 1](LAB_03(image)/ex1.png)

---

## Exercise 2: Self-Describing Bootstrap

### What I did
I wrote `labs/lab-03-ec2/user-data-db.sh`. The script installs PostgreSQL 15, starts it, creates a database called `usms`, and writes a marker file at `/var/log/usms-db-bootstrap.done` with the instance ID and the UTC time.

To make it idempotent, the script checks for the marker file first:

```bash
if [ -f "$MARKER" ]; then
  echo "Marker $MARKER already present - bootstrap already ran. Exiting."
  exit 0
fi
```

So if it runs a second time, it just exits and doesn't change anything.

Before launching, I checked it with `bash -n` and it passed. The file is 970 bytes, which is well under the 16 KB limit. Then I launched `usms-db-02` in `usms-private-subnet-b` with `usms-db-sg` and this script as user data.

![Exercise 2 - syntax check and size](LAB_03(image)/ex2.1.png)

![Exercise 2 - launching usms-db-02](LAB_03(image)/ex2.2.png)

### Why the outer heredoc is quoted
I quoted it (`<< 'EOF'`) so that things like `$(date)`, `$MARKER` and `$TOKEN` get saved into the file as text and only run later on the instance, not on my own machine when I create the file.

### When could it actually run twice?
User data normally only runs on the first boot, but there are some cases where it can run again:

- If someone runs `cloud-init clean` and reboots, or runs the script again by hand while debugging.
- If cloud-init is set up to run the script on every boot.
- If an AMI is made from this instance and a new instance is launched from it. The new instance has a new ID, so cloud-init thinks it's a first boot and runs the user data again. The marker file is already inside the image, so the script exits instead of setting up the database again.

### Byte-for-byte check
I used the same method as Step 12 to compare my script with what EC2 stored:

```bash
aws ec2 describe-instance-attribute --instance-id "$DB2_INSTANCE_ID" \
  --attribute userData --query 'UserData.Value' --output text > outputs/lab-03-ex2-userdata.b64

openssl base64 -d -A -in outputs/lab-03-ex2-userdata.b64 -out outputs/lab-03-ex2-userdata.sh

diff labs/lab-03-ec2/user-data-db.sh outputs/lab-03-ex2-userdata.sh
```

The expected result was no output from `diff`, but I got a MISMATCH.

![Exercise 2 - diff result](LAB_03(image)/ex2.mismatch.png)

### Limitation found
Floci didn't return any user data. The CLI printed `None`, and when I decoded the word `None` as base64 it turned into a few random bytes (`6@@`). That's why the diff shows my whole script on one side and almost nothing on the other.

I got the same result for `usms-web-01` in Step 12, so this is a Floci problem and not a problem with my script. On real AWS the decoded file would match exactly and `diff` would print nothing.

---

## Exercise 3: Reachability Report

### What I did
I wrote `scripts/utilities/lab-03-reachability.sh`. For every running instance tagged `Project=USMS`, it prints the name, private IP, public IP, a verdict and a reason. The verdict only uses the route table and the security group, not the instance name or tags.

The rules I used:

| Situation | Verdict |
|---|---|
| Has public IP, subnet has an igw route, SG allows port 80 | REACHABLE |
| Has public IP, but igw route or SG rule is missing | UNREACHABLE |
| No public IP, but subnet has an igw route | NO-ADDRESS |
| No public IP and no igw route | UNREACHABLE |

The script finds its own folder using `${BASH_SOURCE[0]}`, so it works from any directory. There are no hard-coded IDs; everything is looked up by tag.

### About `set -e`
I used `set -uo pipefail` but left out `-e`. Some lookups are supposed to return `None`, like the public IP of a private instance. With `-e`, one failed lookup could stop the whole report, and I want it to keep going and still print the other instances. I explained this in a comment at the top of the script.

### Verification
I ran it from the repo folder and from my home folder. Both gave the same output:

| Name | Verdict | Reason |
|---|---|---|
| usms-db-01 | UNREACHABLE | has address but igw route or sg rule missing |
| usms-db-02 | UNREACHABLE | has address but igw route or sg rule missing |
| usms-admin-01-host | REACHABLE | igw route + sg allows 80/tcp from 0.0.0.0/0 |
| usms-web-01 | REACHABLE | igw route + sg allows 80/tcp from 0.0.0.0/0 |

![Exercise 3 - run from repo folder](LAB_03(image)/ex3.1dir.png)

![Exercise 3 - run from home folder](LAB_03(image)/ex3.2dir.png)

### Limitation found
The two database instances show as UNREACHABLE, which is correct, but the reason is wrong. Floci gives every instance a public IP of `127.0.0.1`, even in private subnets, so the script thinks they have an address. On real AWS they would have no public IP and the reason would say "no igw route on subnet". The script logic is fine; the problem is the data Floci returns.

---

## Exercise 4: Right-Size and Clean Up

### The situation
The portal has around 400 users at peak, mostly just reading pages. The one t3.micro is at 85% CPU at midday and does almost nothing at night. Finance wants to know the cost before anything changes.

### What CPU credits are and why 85% is a problem
T3 instances are "burstable". They don't get full CPU all the time. They earn credits at a baseline rate and spend them when they go above that.

For a t3.micro:
- 2 vCPUs, baseline of 10% per vCPU
- earns 12 credits per hour
- at 85% on both vCPUs it uses about 102 credits per hour
- so it loses about 90 credits every hour

It can only save up to 288 credits, so a full balance is gone in around 3 hours at 85%. After that, it depends on the credit mode:

- **Standard mode:** the CPU gets throttled back to 10%. The site gets slow right at the busiest time.
- **Unlimited mode** (the default for t3): it keeps running fast, but AWS charges extra, about $0.05 per vCPU-hour. Running 1.5 vCPUs above baseline costs about $0.075 per hour, which is around 7 times the price of the instance itself.

So either the users suffer or the bill goes up, and you can't tell which just by looking at the instance type.

### Scale up or scale out?
**Scale up** means switching to one bigger instance, like a t3.medium. It's easy, and no load balancer is needed. But a t3.medium still has only a 20% baseline, so 85% is still too high. It also doesn't help with the night, because you pay for the bigger instance all day. And if that one instance or its AZ goes down, the whole site is down.

**Scale out** means running two or more small instances behind a load balancer, with Auto Scaling. Since the traffic is mostly reads, it spreads well across servers. At night Auto Scaling can drop down to one instance, so we don't pay for capacity we aren't using. It also puts servers in two AZs, so one AZ failing doesn't take the site down.

I would choose **scale out**. It fixes the CPU problem, the wasted night hours and the single point of failure. This is also what Lab 05 (load balancer) and Lab 06 (auto scaling) build next.

### Cost comparison (us-east-1, Linux, on-demand)

| Option | How I worked it out | Per month (approx.) |
|---|---|---|
| A. Keep 1 t3.micro (unlimited) | $7.59 + extra credits (about $0.075/hr x 4 peak hours x 30 days = about $9) | about $16.60 |
| B. Scale up to 1 t3.medium | $0.0416/hr x 730 hrs | about $30.37 |
| C. Scale out to 2 t3.micro + ALB | 2 x $7.59 + ALB about $16.43 + small LCU charge | about $32 to $35 |
| C, but 1 instance at night | roughly half the hours on 1 instance | about $28 to $31 |

Prices used: t3.micro $0.0104/hr, t3.medium $0.0416/hr, ALB about $0.0225/hr.

Option A looks cheapest, but it has no backup server and the extra charges grow as traffic grows. Option C costs about the same as B, but it gives two AZs and can shrink at night.

Sources:
- AWS EC2 On-Demand Pricing: https://aws.amazon.com/ec2/pricing/on-demand/
- AWS docs, unlimited mode for burstable instances: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/burstable-performance-instances-unlimited-mode-concepts.html
- Elastic Load Balancing pricing: https://aws.amazon.com/elasticloadbalancing/pricing/

### Checking the credit mode
The hint says to check the credit mode with `aws ec2 describe-instance-credit-specifications`. I tried it on `usms-web-01`, but Floci said the operation is not supported. On real AWS it would show `standard` or `unlimited`.

### What I deleted
These are in the right order. I didn't touch anything in the KEEP list from Section 16.

**1. Terminate the admin host from Exercise 1**

> **What will be deleted:** usms-admin-01-host (i-9b5013104c797ef06) and its root volume.
> **What depends on it:** nothing; it was never put in lab-03.env.
> **Reversible?** No, a terminated instance can't be started again.
> **Effect on later labs:** none, Labs 4 to 6 don't use it.

```bash
aws ec2 terminate-instances --instance-ids i-9b5013104c797ef06
aws ec2 wait instance-terminated --instance-ids i-9b5013104c797ef06
```

**2. Look for orphaned volumes**

> **What will be deleted:** only volumes with status `available`, meaning not attached to anything.
> **What depends on it:** nothing, since they aren't attached.
> **Reversible?** No, so I checked the list before deleting.
> **Effect on later labs:** none, as long as usms-web-data-vol isn't in the list (it's attached, so it won't be).

```bash
aws ec2 describe-volumes --filters Name=status,Values=available \
  --query 'Volumes[].{Id:VolumeId,Name:Tags[?Key==`Name`]|[0].Value}' --output table
# if anything shows up:
# aws ec2 delete-volume --volume-id <id>
```

**3. Look for unassociated Elastic IPs**

> **What will be deleted:** nothing in my case (explained below).
> **What depends on it:** usms-nat-eip is used by the NAT gateway from Lab 2.
> **Reversible?** No. Once released you probably won't get the same IP back.
> **Effect on later labs:** releasing the NAT's IP would break internet access for the private subnets, which Lab 04 needs.

```bash
aws ec2 describe-addresses \
  --query 'Addresses[?InstanceId==null].{Alloc:AllocationId,IP:PublicIp}' --output table
```

The only one that showed up was `eipalloc-102cc4a44c0ba0c80` (54.228.205.51). That's the NAT gateway's IP. It shows no instance because it's attached to the NAT gateway, not to an instance. So it's not really unused, and I kept it. `usms-web-eip` is still attached to usms-web-01.

![Exercise 4 - termination and Elastic IP check](LAB_03(image)/ex4.1.png)

### Verification
After the cleanup I ran `verify-lab-03.sh` again. The exercise expects FAIL=0, but I got `PASS=33 FAIL=3`, the same as before the cleanup. The 3 failures are the Floci limitations explained in my report (user data not returned, fake public IP on the DB instance, and AMI creation not supported). Since the result didn't change, the cleanup didn't break anything I need to keep.

![Exercise 4 - verify after cleanup](LAB_03(image)/ex4.2.png)

---

## Exercise 5: S3 Hand-Off Prep

### What I did
I wrote `labs/lab-03-ec2/transcript-upload.sh`. It is meant to run on usms-web-01. It takes a student ID and a file path, and uploads the file to `s3://usms-student-data/transcripts/<student-id>/<filename>`.

- If either argument is missing, it prints a usage message and exits with code 1.
- It also checks that the file exists.
- It doesn't use or mention any access keys. The AWS CLI on the instance gets temporary credentials from the instance profile on its own.

I checked the script with `bash -n` and grepped it for anything that looks like key material, and nothing came up.

### Why I didn't need to add an outbound rule
`usms-app-sg` already has the default outbound rule that allows all traffic to `0.0.0.0/0`, and that's what lets the HTTPS request to S3 on port 443 go out. Security groups are stateful, so the reply from S3 is allowed back in without an inbound rule.

![Exercise 5 - script check and outbound rule](LAB_03(image)/ex5.1.png)

### Readiness file
I wrote `outputs/lab-03-s3-readiness.txt`. I ran head-bucket like this so the error is saved and doesn't stop the script:

```bash
HEAD_BUCKET_OUTPUT=$(aws s3api head-bucket --bucket usms-student-data 2>&1); HEAD_BUCKET_EXIT=$?
```

What the file contains:

| Item | Value |
|---|---|
| Instance ID | i-f800b74909dd60e31 |
| Instance profile ARN | arn:aws:iam::000000000000:instance-profile/usms-ec2-app-profile |
| Role | usms-ec2-app-role |
| Policy | USMSStudentDataReadWrite |
| Bucket ARN in policy | arn:aws:s3:::usms-student-data (and /*) |
| head-bucket exit code | 255 |
| head-bucket output | An error occurred (404) when calling the HeadBucket operation: Not Found |

The 404 is what I expected, because the bucket doesn't exist yet. Everything on the EC2 side is ready; it's just waiting for the bucket. The exercise says Lab 4 creates the bucket, but in the Lab 04 page, Lab 04 is ECS and the bucket gets made in Lab 10. Once it's created, the upload should work without changing anything on the instance, role or policy.

![Exercise 5 - readiness file](LAB_03(image)/ex5.2.png)

### Bucket name in the env file
The exercise says to add `USMS_BUCKET_NAME` to `configs/lab-03.env` only if `lab-01.env` doesn't already have it. `lab-01.env` already had `USMS_BUCKET_NAME=usms-student-data`, so nothing was added. I sourced the file to double check.

![Exercise 5 - bucket name check](LAB_03(image)/ex5.3.png)

---

## Summary

| Exercise | Result |
|---|---|
| 1 | Admin host launched in us-east-1b with no profile, later removed in Exercise 4 |
| 2 | Idempotent DB bootstrap script written and used for usms-db-02; byte check failed because of Floci |
| 3 | Reachability script works from any folder; DB reason is off because of Floci's fake IPs |
| 4 | Recommended scaling out, compared costs, deleted the admin host, kept the NAT IP |
| 5 | Upload script with no keys and a readiness file; bucket check gives 404 as expected |

Some things didn't work fully in Floci (user data, credit specs, and the fake IPs), so I wrote down what would happen on real AWS for each one.