# Lab 04 Notes

**Floci support path (Step 3): B - ECS only.**

- ECS is supported. The `describe-services` probe failed only because the
  cluster "probe" does not exist (`ClusterNotFoundException: Cluster not found: probe`),
  not because the API is missing.
- CloudWatch and CloudWatch Logs are supported.
- Application Auto Scaling is NOT supported in this Floci build:
  `UnknownOperationException: Unknown operation: AnyScaleFrontendService.DescribeScalableTargets`.
  The same applies to describe-scaling-policies and describe-scheduled-actions.

This does not affect Lab 04, which only uses ECS. It will matter in Lab 06,
which uses the documented fallback for Path B.

---

## Review Questions

### Q1. "I put auto scaling on the task definition"

That sentence is wrong in a few ways. Auto scaling doesn't go on the task definition at all. In Lab 06 it will be attached to the **service**, `usms-enrolment-svc`, which gets registered as a scalable target in Application Auto Scaling. The only thing auto scaling ever changes is one number, the service's `desiredCount`. It doesn't start or stop tasks and it doesn't touch the task definition, which can't be changed anyway. The **service** is the object that does the actual work: it notices that the running count doesn't match the desired count and starts or stops tasks until they match.

Because ECS itself knows nothing about the scalable target, there's a visible side effect. If someone sets the desired count by hand (like I did in Step 11), ECS just accepts it, and later the scaling policy changes it again to whatever it thinks is right. The manual change silently gets overwritten, and nothing in `describe-services` tells you a scaling policy exists. You'd have to look in Application Auto Scaling to find out.

### Q2. One policy, two kinds of compute

Lab 1 wrote `USMSStudentDataReadWrite` for a bucket that didn't exist. In Lab 3 it was attached to `usms-ec2-app-role`, which reaches the EC2 instance through the instance profile `usms-ec2-app-profile`. At runtime, the instance asks the Instance Metadata Service at 169.254.169.254 for credentials, and AWS hands back temporary keys for that role. In this lab the exact same policy, unchanged, is attached to `usms-ecs-task-role`, and the task definition names that role in `taskRoleArn`. At runtime, ECS puts a variable called `AWS_CONTAINER_CREDENTIALS_RELATIVE_URI` into the container, and the AWS SDK uses it to fetch temporary keys for the task role from a local endpoint. So the mechanism is different (metadata service vs container credentials endpoint), but the result is the same: short-lived credentials that rotate on their own, so neither the instance nor the container ever needs an access key saved on disk or baked into an image. Right now the policy grants access to an ARN where nothing exists, so any S3 call would just fail with "bucket not found". The moment a bucket is finally created at `arn:aws:s3:::usms-student-data` (in Lab 10), both the EC2 instance and the Fargate task can read and write it at the same instant, without changing the policy, either role, the instance profile or the task definition.

### Q3. Execution role vs task role

- **Execution role:** "the task never even starts, and the stopped reason talks about pulling the image or creating the log stream."
- **Task role:** "the task starts and runs fine, but the app gets AccessDenied when it tries to use S3 (or another AWS service)."

Both roles have the same trust policy because both are assumed by the same service principal, `ecs-tasks.amazonaws.com`. The trust policy only says *who is allowed* to assume the role, and that's ECS tasks in both cases. The difference is *who actually uses it and when*: the execution role is used by the ECS/Fargate agent before my container exists, and the task role is used by my application code while the container is running. That's why I could reuse `policies/trust-ecs-tasks.json` for both.

### Q4. Why the security group points at a group, not a CIDR

Even if the task count never changed, using `usms-app-sg` as the source is still the right choice. A CIDR like `10.0.1.0/24` would let in anything in that subnet, including the NAT gateway or any new instance someone launches there later, not just the web tier. The rule I want is "only the web servers can call the enrolment API", and a group reference says exactly that. It also keeps working if the web server gets a new IP or moves to another subnet.

Once Lab 06 lets the task count change on its own, it becomes close to mandatory. Each Fargate task gets its own network interface with a new private IP, and auto scaling will keep creating and removing tasks in two subnets. If any rule depended on task IPs, it would be wrong every time the service scaled. Security group references follow whatever instances or tasks carry the group, so they don't need updating when IPs change.

### Q5. What Fargate removes and what it doesn't

Fargate removes the servers. In Lab 3 I had to pick an AMI, an instance type, a key pair, attach volumes and think about patching. With the EC2 launch type for ECS I would also have to run and scale a fleet of instances for the tasks to land on. On Fargate I only say how much CPU and memory each task needs (256 / 512, then 1024 in Exercise 2), and AWS finds somewhere to run it.

What Fargate does **not** remove is the networking from Lab 2. In `awsvpc` mode every task gets its own network interface in my subnet, with its own private IP and its own security group (`usms-enrolment-sg`), exactly like an EC2 instance. It still follows my route tables too: my tasks are in the private subnets, so to pull the nginx image they have to go through `usms-private-rt` to `usms-nat` and then out through `usms-igw`. If the NAT gateway from Lab 2 were missing, the service would be created fine but every task would fail to start because it couldn't pull the image.

### Q6. A command that proves persistence and one that doesn't

`aws sts get-caller-identity` would look exactly the same in memory mode and hybrid mode, because the Floci account (000000000000) and root ARN are fixed values. Getting the same answer after a restart proves nothing about whether my resources were saved.

A command that does show the difference is `aws ecs describe-clusters --clusters usms-ecs-cluster` (or `aws ecs describe-services --cluster usms-ecs-cluster --services usms-enrolment-svc`) after stopping and starting Floci. In hybrid mode the cluster and service are saved to disk, so they come back as ACTIVE. In memory mode everything is wiped when the container stops, so the same command would fail with ClusterNotFoundException or return a MISSING failure. The difference is that this command reads something I created, which only exists if storage actually kept it, while the identity check reads something Floci always gives back no matter what.