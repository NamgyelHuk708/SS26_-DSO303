# Lab 6 Independent Exercises

My Floci build is on **Path C**: Application Auto Scaling isn't implemented (`UnknownOperationException`). Exercises 1 and 2 need that API, so I did them as templates and written answers. Exercise 3 I built so it handles the missing API. Exercises 4 and 5 are the ones the lab says to focus on for Path C, and I did them in full.

---

## Exercise 1: A Memory Policy and a Scale-Out-Only Policy

### What I did
I couldn't create the policy (`put-scaling-policy` returns `UnknownOperationException`), so I wrote its configuration as a template. It uses a quoted heredoc, because there are no variables in it:

```bash
cat > templates/lab-06-target-tracking-memory.json << 'EOF'
{
  "TargetValue": 70.0,
  "PredefinedMetricSpecification": { "PredefinedMetricType": "ECSServiceAverageMemoryUtilization" },
  "ScaleOutCooldown": 60,
  "ScaleInCooldown": 600,
  "DisableScaleIn": true
}
EOF
python3 -m json.tool templates/lab-06-target-tracking-memory.json > /dev/null && echo "valid JSON"
```

On real AWS, this would have been created with the same `put-scaling-policy` command as the CPU policy, just a different policy name and file. It wouldn't go in `configs/lab-06.env`, because Exercise 4 removes it.

**Would the verify script still pass?** Yes. None of its checks look for a memory policy, and none count the total number of policies or require the managed alarm count to be exactly 4 (only "2 or more").

### Answers
- **Why five managed alarms and not six?** With `DisableScaleIn: true`, the policy can never scale in, so AWS doesn't create its **AlarmLow**. That means there's nothing watching for "memory is low enough to remove a task" for this policy. It can only ever add tasks.
- **Memory 70 or CPU 50, which scales out first?** I can't tell by guessing. I'd need to know whether the enrolment app runs out of CPU or memory first under load, which means running a load test while graphing both metrics.
- **Does this policy change how the other two scale in?** No. A target tracking policy with `DisableScaleIn: true` doesn't take part in scale-in decisions, so the CPU and request policies can still scale in when they both agree. It only adds one more "yes" voice for scaling out.

---

## Exercise 2: The Scale-In Half of Step Scaling

### What I did
I wrote the scale-in step configuration as a template:

```bash
cat > templates/lab-06-step-scaling-in.json << 'EOF'
{
  "AdjustmentType": "ChangeInCapacity",
  "MetricAggregationType": "Average",
  "Cooldown": 300,
  "StepAdjustments": [
    { "MetricIntervalLowerBound": -10, "MetricIntervalUpperBound": 0, "ScalingAdjustment": -1 },
    { "MetricIntervalUpperBound": -10, "ScalingAdjustment": -2 }
  ]
}
EOF
python3 -m json.tool templates/lab-06-step-scaling-in.json > /dev/null && echo "valid JSON"
```

The low alarm would be `usms-enrolment-queue-low`: Average **< 20** for **3 × 60 s**, with this policy as its only action. On real AWS I'd publish values down to 5, force the alarm with `set-alarm-state`, and then delete both objects (the alarm first, then the policy, each with the four-line warning). On my build the policy couldn't be created, so there was nothing to attach the alarm to or to delete.

### The signs
| Part | Sign | Why |
|---|---|---|
| Interval bounds | 0 or negative | It's a scale-**in** policy, so the metric is *below* the threshold. A metric of 5 against a threshold of 20 is a breach of **-15** |
| Adjustments | negative | Removing tasks |

- `MetricIntervalUpperBound: 0` with `ScalingAdjustment: -1` means: **when the metric is between 10 and 0 below the threshold (between 10 and 20), remove 1 task.**
- A breach of -15 falls in the second interval (below -10), so -2 would apply.
- **The cooldown is 300 s, longer than the scale-out's 60 s,** because removing capacity too fast is the expensive mistake. If traffic comes back, you're short of tasks for minutes.
- **The unreachable step:** the service sits at the floor of 2 tasks most of the time, so **-2** would take it to 0. MinCapacity is 2, so it gets clamped, and the "remove 2" step can never actually remove 2 tasks from the baseline. It's a finding, not a bug.

### Paragraph: a step policy on CPU next to target tracking on CPU
If someone added a step policy on CPU with its own alarm at 60%, it would fight the CPU target tracking policy. Target tracking calculates the number of tasks that should bring average CPU to 50%, and sets that. The step policy doesn't care about 50%. It adds a fixed number of tasks whenever CPU crosses 60. So one controller adds tasks the other one thinks aren't needed, then target tracking's low alarm removes them again, and the service keeps going up and down (oscillating). I would keep **target tracking**, because it works out the right capacity in one move for a utilisation metric. Step scaling should be kept for signals that aren't utilisations, like the queue depth.

---

## Exercise 3: A Scaling Report Tool

### What I did
I wrote `scripts/utilities/usms-scaling-report.sh`. It:
- finds every scalable target in the `ecs` namespace whose cluster name starts with `usms-`, without hard-coding any names
- gets each target's policies and the service's current desired count
- prints a verdict computed from the target's own fields

Verdict order, top to bottom:

| Verdict | When |
|---|---|
| PINNED | MinCapacity = MaxCapacity |
| FROZEN | any suspension switch is true |
| AT-CEILING | desiredCount = MaxCapacity |
| AT-FLOOR | desiredCount = MinCapacity and more than one policy |
| ELASTIC | none of the above |

**FROZEN comes before AT-CEILING** because a suspended target can't move at all. That's the more serious problem, even if it also happens to be at its ceiling. PINNED comes first because if min equals max, nothing can ever change, whatever else is true.

**About `set -e`:** I used `set -uo pipefail` without `-e`. Some Application Auto Scaling calls might not be implemented, and one missing API should be reported, not abort the whole report.

**Handling the missing API:** if `describe-scalable-targets` fails, the script prints the error, writes `{"available": false, "targets": []}` to `outputs/lab-06-scaling-report.json`, and exits cleanly.

### Verification
On my build, both runs (from the repo and from my home folder) gave the same output:

```
Application Auto Scaling is not available on this endpoint:
  An error occurred (UnknownOperationException) when calling the DescribeScalableTargets operation: ...
```

![Exercise 3 - report tool on Path C](LAB_06(image)/ex3.png)

On real AWS it would print the full table: `service/usms-ecs-cluster/usms-enrolment-svc`, min 2, max 10, desired 2, ELASTIC, the two target tracking policies, the step policy and the two scheduled actions.

---

## Exercise 4: The Enrolment-Week Capacity Plan

### Is it solved? (three sentences)
1. Reactive scaling will handle the "double normal traffic for three weeks" well, adding tasks as CPU or requests go up.
2. It will handle sudden spikes badly, because every scale-out has to wait for an alarm, a task start and a grace period.
3. In the first twenty minutes of a cohort day it would be about 5 minutes late and capped at 10 tasks, so on its own it would fall over again just like last year.

### Why 40× traffic isn't a scaling-speed problem

**Time for a reactive policy to add capacity (this lab's numbers):**

| Term | Seconds | Where it's set |
|---|---|---|
| High alarm: 3 periods × 60 s | 180 | AWS's managed alarm for target tracking |
| Policy invocation | ~0 | – |
| Fargate task start | 20–60 | AWS figure (my Floci took 18.4 s for 2 → 4, see Ex 5) |
| Load balancer grace period | 60 | Lab 05 service setting |
| **First new task serving traffic** | **≈ 260–300 (about 5 min)** | |

Target tracking can jump straight to the computed number in one move, so 2 → 10 could also be serving at about 5 minutes. With the step policy (+3 per action, 60 s cooldown): 2 → 5 at about 60 s, 5 → 8 at about 120 s, 8 → 10 at about 180 s, plus the start and grace period, so the last tasks are serving at about 5 minutes too.

**Capacity vs throughput:** the ceiling is 10 tasks × a target of 1000 requests per task per minute = **10,000 requests per minute ≈ 167 requests per second**. If "normal" is what the 2 baseline tasks handle at the target (2 × 1000 = 2,000 per minute, which is my assumption), then 40× normal = **80,000 per minute**, which needs **80 tasks**. A ceiling of 10 can only serve **5× normal**. So the real problem is the **ceiling** (and not knowing what one task can serve), not how fast scaling reacts.

### The ceiling, checked against the subnets
Each private subnet is a /24, which is 256 addresses. **AWS reserves 5 addresses in every subnet** (the first four and the last one), leaving **251 usable** (source: https://docs.aws.amazon.com/vpc/latest/userguide/subnet-sizing.html).

Already in use:
- `usms-private-subnet-a` (10.0.3.0/24): `usms-db-01` (and its duplicate from Lab 3) plus the running tasks
- `usms-private-subnet-b` (10.0.4.0/24): `usms-db-02` plus the running tasks

That leaves roughly **248 + 250 ≈ 495** addresses for tasks. Every awsvpc task uses one address, so the subnets could hold far more than 10 tasks, or even 80. The subnets are not the limit.

### Capacity plan
Assuming enrolment opens on the 14th and the three cohort days are the 14th, 21st and 28th (to be confirmed by the project lead):

| Action | Command (key parts) | Bounds |
|---|---|---|
| Raise the ceiling for enrolment | `register-scalable-target --max-capacity 80` | max 80 |
| Start of the 3-week window | `put-scheduled-action --schedule "at(2026-MM-14T07:00:00)" --timezone Asia/Thimphu` | min 4, max 80 |
| Each cohort morning (×3) | `--schedule "at(2026-MM-14T07:30:00)"` (and the 21st, 28th) | min 40, max 80 |
| End of each cohort morning (×3) | `--schedule "at(2026-MM-14T09:30:00)"` (and the 21st, 28th) | min 4, max 80 |
| End of the window | `--schedule "at(2026-MM-04T20:00:00)"` | min 2, max 10 |
| Request target | change only after a load test | – |

- **Reversible in one command:** every scheduled action (`delete-scheduled-action`) and the bounds (`register-scalable-target` again).
- **Not reversible:** a Fargate vCPU quota increase request (it's free, but you can't take it back). New accounts have a small Fargate vCPU limit, so this needs checking before raising the ceiling to 80.
- `at()` actions don't delete themselves after firing, so the runbook should include deleting them after the window.

### Monthly cost (enrolment month)
Fargate prices for us-east-1 Linux/x86: $0.04048 per vCPU-hour and $0.004445 per GB-hour (https://aws.amazon.com/fargate/pricing/). A task in `configs/lab-04.env` is 0.25 vCPU and 1 GB, so one task costs **$0.014565 per hour**.

| Item | Working | Cost |
|---|---|---|
| Baseline (normal month) | 2 tasks × 730 h | **$21.26** |
| 3-week floor of 4 | +2 tasks × 504 h | +$14.68 |
| 3 cohort mornings at 40 | +36 tasks × 2 h × 3 days | +$3.15 |
| Reactive extra for "double traffic" (assumed +2 tasks, 8 h/day, 21 days) | 2 × 168 h | +$4.89 |
| CloudWatch alarms (about 5 × $0.10) | https://aws.amazon.com/cloudwatch/pricing/ | +$0.50 |
| Custom metric (1 × $0.30) | same page | +$0.30 |
| **Enrolment month total** | | **≈ $44.80** |

So enrolment month costs about twice a normal month, and most of the extra is the three-week floor of 4, not the short peaks. CloudWatch alarms and custom metrics are small here but are often forgotten, and they grow with every policy (two alarms per target tracking policy).

### What I need from the project lead
1. **A load test result:** how many requests per second one 0.25 vCPU / 1 GB task can handle before response times get bad. Every target value in this lab (50% CPU, 1000 requests) is a guess until this is measured (§12.4).
2. **The exact cohort dates and opening times,** so the scheduled actions fire at the right moment.
3. **Approval** to raise the ceiling to about 80 tasks and request the Fargate vCPU quota, plus the budget (about $45 for that month instead of $21).

### Tidy-up
Exercise 1's memory policy and Exercise 2's step-in policy and low alarm were **never created** on my build, because Application Auto Scaling isn't available. So there was nothing to delete. On real AWS the order would be:

> **What will be deleted:** usms-enrolment-memory-target-tracking (Exercise 1).
> **What depends on it:** nothing; its single managed alarm is deleted with it.
> **Reversible?** Yes, put-scaling-policy with templates/lab-06-target-tracking-memory.json.
> **Effect on later labs:** none.

```bash
aws application-autoscaling delete-scaling-policy --service-namespace ecs \
  --resource-id service/usms-ecs-cluster/usms-enrolment-svc \
  --scalable-dimension ecs:service:DesiredCount \
  --policy-name usms-enrolment-memory-target-tracking
```

`verify-lab-06.sh` gave the same **PASS=23 FAIL=19** as in the main lab, so nothing changed.

---

## Exercise 5: The Hand-Off to Lab 10

### The export script
I wrote `scripts/utilities/usms-scaling-history.sh`. It:
- finds the resource ID from the ECS service ARN (nothing hard-coded)
- collects the scalable target, the policies, the scheduled actions, the scaling activities (including not-scaled ones), the alarms and the service
- saves everything as one JSON document with a `generated` UTC timestamp from python3 and a `resourceId` field

Every Application Auto Scaling section is stored as `{"error": "not available on this endpoint"}` instead of crashing. The file `outputs/lab-06-scaling-history.json` is valid JSON and **3,065 bytes**.

![Exercise 5 - export](LAB_06(image)/ex5.1-export.png)

### Measuring how long capacity takes to appear
The exercise wants this measured by re-registering the target with MinCapacity 4. That isn't possible on my build, so I used a substitute: `update-service --desired-count 4`, timed with python3 until `runningCount` equalled `desiredCount`, then set it back to 2.

```
start=2026-10-11T12:24:24Z end=2026-10-11T12:24:43Z from=2 to=4 elapsed=18.4s
method: update-service --desired-count (substitute; register-scalable-target unavailable on Floci)
AWS-documented Fargate start: ~20-60 s per task
```

18.4 s is faster than real Fargate (20–60 s, plus the 60 s grace period before the load balancer counts it), so Lab 10 should use the AWS figure, not this one. The service is back at desired 2.

![Exercise 5 - latency](LAB_06(image)/ex5.2-latency.png)

### lab-06.env
I appended two variables, derived rather than typed: `USMS_SCALING_HISTORY_FILE=outputs/lab-06-scaling-history.json` and `USMS_SCALE_LATENCY_SECONDS=18.4`. The export count went from 22 to **24**, and there are still no empty values.

### Readiness file for Lab 10
`outputs/lab-06-lab10-readiness.txt` (copied into this folder) contains:

| Item | Value |
|---|---|
| Scaling history file | `outputs/lab-06-scaling-history.json` (3065 bytes) |
| Scale-out latency | 18.4 s (substitute on Floci); AWS: about 20–60 s per task |
| Task role ARN | `arn:aws:iam::000000000000:role/usms-ecs-task-role` |
| Bucket ARNs in the policy | `arn:aws:s3:::usms-student-data` and `arn:aws:s3:::usms-student-data/*` |
| Permissions | s3:GetObject, s3:PutObject, s3:ListBucket; s3:DeleteBucket denied |
| head-bucket | `An error occurred (404) when calling the HeadBucket operation: Not Found`, exit code **255** |

The bucket ARNs were **read from the IAM policy document** with `get-policy` and `get-policy-version`, not typed. I recorded **both**, because the policy needs the bucket ARN for `ListBucket` and the `/*` ARN for getting and putting objects.

After Lab 10 Step 1 creates `usms-student-data`, the same `head-bucket` will return exit code **0**. At that same instant, `usms-ecs-task-role` (and `usms-ec2-app-role` from Lab 3) can actually read and write the bucket, without any change to either role or to the policy.

![Exercise 5 - readiness file](LAB_06(image)/ex5.3.png)

---

## Summary

| Exercise | Result on my build (Path C) |
|---|---|
| 1 | Memory policy written as a template (target 70, DisableScaleIn true); answers on paper |
| 2 | Scale-in step template with the sign rules explained; the -2 step is unreachable at the floor of 2 |
| 3 | Report tool that handles the missing API cleanly from any folder |
| 4 | Reactive scaling is about 5 min late and capped at ~167 req/s; plan with scheduled floors and a ceiling of 80; about $45 vs $21 a month |
| 5 | Scaling history export (3065 bytes), latency 18.4 s (substitute), Lab 10 readiness with the bucket ARNs read from the policy |