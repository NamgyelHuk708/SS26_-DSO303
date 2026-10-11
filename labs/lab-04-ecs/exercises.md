# Lab 4 Independent Exercises

---

## Exercise 1: A Second Service (usms-results-svc)

### What I did
I created `usms-results-svc` in `usms-ecs-cluster` using the same `usms-enrolment` task definition family. It has a desired count of 1, runs in both private subnets, uses `usms-enrolment-sg`, and has no public IP. Every ID came from the env files, nothing was typed by hand.

```bash
RESULTS_ARN=$(aws ecs create-service \
  --cluster "$USMS_ECS_CLUSTER" \
  --service-name usms-results-svc \
  --task-definition "$USMS_ENROLMENT_TASK_FAMILY" \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$USMS_PRIVATE_SUBNET_A,$USMS_PRIVATE_SUBNET_B],securityGroups=[$USMS_ENROLMENT_SG],assignPublicIp=DISABLED}" \
  --enable-ecs-managed-tags \
  --propagate-tags SERVICE \
  --tags key=Name,value=usms-results-svc key=Project,value=USMS key=Tier,value=app key=Lab,value=04 key=Service,value=results \
  --query 'service.serviceArn' --output text)
```

What changed compared to the enrolment service: the name, the desired count (1 instead of 2) and the extra `Service=results` tag. What had to stay the same: the subnets, the security group, the task definition family and `assignPublicIp=DISABLED`. I didn't add this service to `configs/lab-04.env` because Exercise 4 removes it.

### Verification
`describe-services` for both services returned two ACTIVE services with different desired counts:

| Name | Desired | Status |
|---|---|---|
| usms-enrolment-svc | 2 | ACTIVE |
| usms-results-svc | 1 | ACTIVE |

The verify script doesn't check for extra services, so this didn't make it fail.

![Exercise 1](LAB_04(image)/ex1.png)

---

## Exercise 2: Revision 2 and Updating the Service

### What I did
First I kept a copy of the template that made revision 1, because task definitions can't be edited, and I wanted my files to work the same way:

```bash
cp templates/lab-04-taskdef.json templates/lab-04-taskdef-v1.json
```

Then I made v2 from that copy with `jq`, raising memory from 512 to 1024 MiB (still valid with 256 CPU) and adding `USMS_LOG_LEVEL=info`:

```bash
jq '.memory = "1024"
    | .containerDefinitions[0].environment += [{"name":"USMS_LOG_LEVEL","value":"info"}]' \
  templates/lab-04-taskdef-v1.json > templates/lab-04-taskdef-v2.json
```

The file was valid JSON with no leftover `$` variables. Because `jq` reformats the file, a plain `diff` showed a lot of fake changes, so I compared both files in the same sorted format. That showed only the two real changes:

```bash
diff <(jq -S . templates/lab-04-taskdef-v1.json) <(jq -S . templates/lab-04-taskdef-v2.json)
```

![Exercise 2 - diff and new revision](LAB_04(image)/ex2,1.png)

### A mistake I made
I ran the register command twice by accident, which created `usms-enrolment:3`, an exact copy of revision 2. A revision can't be deleted, only deregistered, so I made it inactive:

```bash
aws ecs deregister-task-definition --task-definition usms-enrolment:3
```

It came back as Rev 3, Status INACTIVE. I checked that revision 2 was saved properly: memory `1024` and four environment variables including `USMS_LOG_LEVEL`.

### Updating the service
```bash
aws ecs update-service --cluster "$USMS_ECS_CLUSTER" --service "$USMS_ENROLMENT_SERVICE" \
  --task-definition usms-enrolment:2
```

The `services-stable` waiter doesn't work on Floci (same error as Step 10), so I used the polling loop instead. It showed desired=2 running=2 on the first try.

### Verification
| Check | Result |
|---|---|
| Service task definition | `usms-enrolment:2` |
| Desired / Running | 2 / 2 |
| `usms-enrolment:1` | still ACTIVE, memory 512 |

![Exercise 2 - service on revision 2, revision 1 still ACTIVE](LAB_04(image)/ex2.2.png)

**One sentence:** the service's `taskDefinition` pointer changed from revision 1 to revision 2, but revision 1 itself didn't change at all and is still ACTIVE, because a revision can't be edited, only replaced.

### Floci note
On real AWS, changing the revision starts a rolling deployment: new tasks on `:2` start before the old `:1` tasks stop, so for a short time there are more than 2 tasks. On Floci, running was already 2 on the first check, so I couldn't see that happen.

After this I re-generated `configs/lab-04.env` so it now records revision 2 and memory 1024, with the baseline desired count still 2.

---

## Exercise 3: ECS Inventory Script

### What I did
I wrote `scripts/utilities/lab-04-ecs-inventory.sh`. It lists every service in the cluster, describes each one, and prints one line with computed verdicts. It also writes the same data to `outputs/lab-04-ecs-inventory.json`.

| Column | Verdict | When |
|---|---|---|
| roles | SAME | executionRoleArn equals taskRoleArn |
| roles | SEPARATE | they're different |
| roles | N/A | one of the roles is missing |
| publicip | RISK | assignPublicIp is ENABLED |
| publicip | OK | assignPublicIp is DISABLED |
| publicip | N/A | no networkConfiguration (e.g. EC2 launch type) |

- No service names are hard-coded. It gets the list from `aws ecs list-services`.
- It finds its own folder using `${BASH_SOURCE[0]}`, so it works from anywhere.
- When there's no data, it prints `N/A` instead of leaving the column empty.

### About `set -e`
I used `set -uo pipefail` but left out `-e`. Some services might have no network configuration or a task definition without a role, and those lookups return `None` or fail. With `-e`, one strange service would stop the whole report, and the services after it wouldn't be checked at all. An inventory that quietly skips services is worse than one that prints N/A. This is explained in a comment at the top of the script.

### Verification
I ran it from the repo folder and from my home folder. Both gave the same output:

```
usms-enrolment-svc   desired=2  running=2  taskdef=usms-enrolment:2   roles=SEPARATE  publicip=OK
usms-results-svc     desired=1  running=1  taskdef=usms-enrolment     roles=SEPARATE  publicip=OK
```

![Exercise 3 - run from repo folder, with JSON](LAB_04(image)/ex3.1.png)

![Exercise 3 - run from home folder](LAB_04(image)/ex3.2.png)

### Something I noticed
`usms-results-svc` shows `taskdef=usms-enrolment` with no revision number. That's because I created it in Exercise 1 with just the family name, and Floci stores exactly what I typed. Real AWS would turn it into the full ARN ending in `:1`, since that was the newest revision when the service was created. The results service is still on revision 1 because Exercise 2 only updated the enrolment service.

This also means the script looked up the roles for "usms-enrolment" without a number, which gives the latest revision (`:2`), not the one this service runs. Both revisions use the same two roles, so SEPARATE is still correct here, but on Floci this could give a wrong answer if a later revision changed the roles. It's a Floci limitation, not a script problem.

---

## Exercise 4: Enrolment Week Capacity Plan

### Why a fixed desiredCount of 2 can't fix the 08:03 problem
`usms-enrolment-svc` has nothing that reads a metric or a clock. The only way its size ever changes is a person running `update-service`, like I did in the Step 11 "Your turn". At 08:00 on Monday nobody is sitting there watching it. Even if they were, a new Fargate task takes 20 to 60 seconds to start on real AWS. So the service stays at 2 tasks while 4,000 students hit it, and it falls over, which is what happened last year at 08:03.

### My plan
These numbers are based on assumptions that should be load tested before going live.

| Item | Number | How I got it |
|---|---|---|
| Students in the first 20 minutes | 4,000 | from the project lead |
| Requests per student | about 5 | log in, list modules, choose, confirm, view result (my assumption) |
| Average load | 20,000 ÷ 1,200 s ≈ 17 req/s | maths |
| Peak load | about 50 req/s | traffic is heaviest in the first few minutes (the crash was at 08:03), so I assumed about 3 times the average |
| What one task can handle | about 10 req/s | assumption for a 0.25 vCPU task, needs testing |
| Tasks needed at peak | 50 ÷ 10 = 5, plus 1 spare = **6** | maths |
| **Minimum** | **2** | one task per Availability Zone |
| **Maximum** | **8** | the 6 for peak plus 2 in case my 10 req/s guess is too high |
| **Scheduled floor** | **6 tasks from 07:30 to 09:00 on enrolment Monday** | scaling on CPU reacts too late: the alarm takes a few minutes, then tasks take up to a minute to start, and the crash happened 3 minutes in |

What each number costs if it's wrong:
- **Minimum 2:** too high means paying for tasks doing nothing at 3am on a Sunday. Too low (1) means one AZ problem takes the whole service down.
- **Maximum 8:** too high means a bug or a flood of fake traffic could scale it up and raise the bill. Too low means it can't handle a bigger year than I planned for.
- **Floor of 6:** too high wastes a small amount of money for 90 minutes. Too low means the 08:03 crash happens again.

For the team building Lab 06: aim for the scheduled floor first, because that's what stops the crash. CPU-based scaling should handle the rest of the week.

### Cost comparison
Fargate prices for Linux/x86 in us-east-1: **$0.04048 per vCPU-hour** and **$0.004445 per GB-hour**.
Source: AWS Fargate pricing, https://aws.amazon.com/fargate/pricing/

Since Exercise 2, each task is 0.25 vCPU and 1 GB:

0.25 × $0.04048 + 1 × $0.004445 = **$0.014565 per task-hour**
× 730 hours = **about $10.63 per task per month**

| Option | Working | Per month |
|---|---|---|
| Fixed at 2 (today) | 2 × $10.63 | about **$21.26**, but it crashes at 08:03 |
| Fixed at 6 (peak) all month | 6 × $10.63 | about **$63.80** |
| Minimum 2 + scheduled 6 for 1.5 hours on enrolment Monday | $21.26 + (4 extra tasks × $0.014565 × 1.5 h) | about **$21.35** |

The scheduled plan costs about 9 cents more than today, but it fixes the crash. Keeping 6 tasks running all month costs three times as much and mostly pays for tasks sitting idle at 3am, which is exactly what finance is complaining about.

### What I switched off
Only the Exercise 1 results service.

> **What will be deleted:** the ECS service `usms-results-svc` from Exercise 1.
> **What depends on it:** nothing. It's not in `lab-04.env` and no later lab uses it.
> **Reversible?** No, but it can be recreated with the Exercise 1 command.
> **Effect on later labs:** none. `usms-enrolment-svc`, which Labs 05 and 06 need, is not touched.

```bash
aws ecs update-service --cluster "$USMS_ECS_CLUSTER" --service usms-results-svc \
  --desired-count 0 --query 'service.desiredCount' --output text

aws ecs wait services-stable --cluster "$USMS_ECS_CLUSTER" --services usms-results-svc \
  || sleep 10

aws ecs delete-service --cluster "$USMS_ECS_CLUSTER" --service usms-results-svc \
  --query 'service.status' --output text
```

I scaled it to 0 first so the tasks would stop properly instead of being killed with `--force`. The waiter gave the same `length()` error as in Step 10, so the `sleep 10` fallback was used.

### Verification
| Service | Status after |
|---|---|
| usms-enrolment-svc | ACTIVE |
| usms-results-svc | INACTIVE |

![Exercise 4 - results service deleted](LAB_04(image)/ex4.1.png)

The exercise says to check `verify-lab-04.sh` reports FAIL=0 afterwards. It gave **PASS=37 FAIL=1**, the same as before the deletion. The one failure is the group-referenced security group rule that Floci doesn't store, so nothing I needed to keep was affected.

![Exercise 4 - verify after deletion](LAB_04(image)/ex4.2.png)

---

## Exercise 5: Closing the Loop Back to Lab 3

### Finding the rule's source group
First I read the source group from the security group itself:

```bash
SRC_GROUP=$(aws ec2 describe-security-groups --group-ids "$USMS_ENROLMENT_SG" \
  --query 'SecurityGroups[0].IpPermissions[0].UserIdGroupPairs[0].GroupId' --output text)
```

It came back `None`, which is the same Floci limitation as Step 8. So I used the group the rule was written with, taken from the file I committed:

```bash
SRC_FILE=$(jq -r '.[0].UserIdGroupPairs[0].GroupId' policies/usms-enrolment-sg-ingress.json)
```

That gave `sg-f79d49ce31a7e5847`, which is `usms-app-sg`.

### Reverse lookup
I asked EC2 which running instance carries that group:

```bash
aws ec2 describe-instances \
  --filters "Name=instance.group-id,Values=$SRC_GROUP" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].InstanceId' --output text
```

This returned **four** instances (`i-79180dfeb7f1774ca`, `i-d296f3224271867fc`, `i-4e256bea4e52d46cb`, `i-f800b74909dd60e31`). That's wrong, because only the web server carries `usms-app-sg`. Floci ignored the `instance.group-id` filter and returned all running instances, the same kind of problem as the NACL tag filter in Lab 2. So I filtered the results myself instead:

```bash
aws ec2 describe-instances --filters "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[?SecurityGroups[?GroupId=='$SRC_GROUP']].InstanceId[]" --output text
```

This returned only `i-f800b74909dd60e31`, which matches `USMS_WEB_INSTANCE` in `configs/lab-03.env`. Verdict: **LOOP CLOSED**.

![Exercise 5 - source group and reverse lookup](LAB_04(image)/ex5.1.png)

### The linkage file
I wrote `outputs/lab-04-lab03-linkage.txt` with the enrolment SG, the source group, the Floci readback (`None`), the instance it resolves to, the lab-03.env web instance and the verdict. It also says the rule is temporary, because Lab 05 removes it once the load balancer becomes the only caller of the enrolment service.

I also added a tag audit with `aws ecs list-tags-for-resource`. This command needs an ARN, not a name, unlike most ECS commands in this lab. Both resources had their tags saved:

| Resource | Tags |
|---|---|
| usms-ecs-cluster | Project=USMS, Tier=app, Name=usms-ecs-cluster |
| usms-enrolment-svc | Project=USMS, Tier=app, Lab=04, Name=usms-enrolment-svc |

So no `tag-resource` fix was needed.

![Exercise 5 - linkage file](LAB_04(image)/ex5.2.png)

Because `outputs/` is git-ignored, I copied the file to `labs/lab-04-ecs/lab-04-lab03-linkage.txt` so it could be committed for Lab 05 to read.

---

## Summary

| Exercise | Result |
|---|---|
| 1 | Created `usms-results-svc` with desired 1 alongside the enrolment service |
| 2 | Registered revision 2 (1024 MiB + log level), moved the service to it, revision 1 still ACTIVE; retired an accidental revision 3 |
| 3 | Inventory script that works from any folder and prints N/A instead of crashing |
| 4 | Capacity plan with min 2, max 8 and a scheduled floor of 6, costed at about $21 vs $64 a month; deleted the results service |
| 5 | Traced `usms-enrolment-sg` back to `usms-web-01` (LOOP CLOSED) even though Floci's server-side filter and rule readback both failed |

The main Floci problems in the exercises were the waiter error, the group rule not being stored, the `instance.group-id` filter being ignored, and the service storing the task definition name without a revision. For each one I worked out what real AWS would show and found another way to check.