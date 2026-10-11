# Lab 06 Notes

**Floci support path (Step 3): C - no Application Auto Scaling.**

- describe-scalable-targets: UnknownOperationException: Unknown operation:
  AnyScaleFrontendService.DescribeScalableTargets (same as Lab 04 Step 3)
- CloudWatch (describe-alarms, put-metric-data, put-metric-alarm, set-alarm-state): SUPPORTED
- IAM / ECS / ELBv2: SUPPORTED

Following the lab's Path C instructions: told my instructor, did the parts that do not
need Application Auto Scaling (custom metric, alarm, templates), Exercises 4 and 5,
and the review questions.

- Step 4: create-service-linked-role -> UnsupportedOperation; get-role -> NoSuchEntity.
  On real AWS this role (path /aws-service-role/ecs.application-autoscaling.amazonaws.com/)
  is what Application Auto Scaling uses to call ecs:UpdateService. Without it,
  register-scalable-target would fail with an error about not being able to assume
  the service-linked role.

---

## Your-turn answers

**Step 6 (MinCapacity 5 while running 2 tasks):** desiredCount would jump to 5 straight away, with no alarm and no policy.
- (a) The **scalable target** made that change. Its floor went up, so it pushed desiredCount up to meet it.
- (b) The cost is paying for 3 extra tasks all night for nothing. `describe-scalable-targets` (the MinCapacity field) would have shown it had changed.

**Step 8 (time from 100% CPU to a third task serving):**
1. High alarm: 3 periods × 60 s = **180 s**
2. Policy invocation: about **0 s**
3. Fargate task start: **20–60 s** (AWS figure; my Floci did 2 → 4 in 18.4 s)
4. Grace period before the load balancer counts it: **60 s** (Lab 05, stored as null on Floci)

Total is about **260–300 s**, roughly 5 minutes. The first one I'd change is the **alarm's 3 evaluation periods**, by using a step policy with my own 1-period alarm. The cost is more false scale-outs on short spikes.

**Step 10 (TreatMissingData on a real system):** I'd choose `breaching`. If the queue-depth metric stops arriving, the most likely reason is that the app has stopped publishing, which is a problem, not "the queue is empty". In this lab I used `notBreaching` only because I published the data by hand.

**Step 11 (one-off at() action):** couldn't be created on my build. An `at()` action stays behind after it fires, so six months later there's an old action in the list that nobody remembers, and if it had raised the floor, the floor stays raised. The runbook page that creates it should also include the `delete-scheduled-action` command and the `register-scalable-target --min-capacity 2` to put the floor back.

---

## The nine-line chain (Step 15)

1. A student clicks Register.
2. Requests per target rises past 1000, or the work queue passes 100. → **this lab** (metric + alarm)
3. An alarm fires and invokes a policy. → **this lab** (alarm → policy)
4. The policy writes desiredCount, clamped to 2..10. → **this lab** (the one integer)
5. ECS starts a task from usms-enrolment:2. → Lab 04
6. The task gets an ENI in usms-private-subnet-a or -b, with no public address. → Labs 02 and 04
7. usms-enrolment-sg admits tcp/80 from usms-alb-sg only. → Lab 05
8. The service registers its address in usms-enrolment-tg. → Lab 05
9. The load balancer health-checks it and, after 60 s of grace, sends it traffic. → Lab 05

On my build, lines 3 and 4 can't run (no Application Auto Scaling). Step 15 block 7 showed the task definition was still `usms-enrolment:2` with one load balancer, so this lab changed nothing about the service.

---

## Section 12.1 for my build

**Observed:**
- the resource ID derived from the service ARN by parameter expansion and validated (3 segments, `service` first)
- the ResourceLabel validated at 6 segments (`app` first, `targetgroup` fourth)
- a step table whose bounds are relative to the threshold, and the step it selects for a breach of 160 (+3)
- a custom metric published into a namespace I made up (USMS/Enrolment)
- an alarm I configured myself, and set-alarm-state moving it to ALARM and back to OK
- the alarm and metric surviving a container restart
- the service unchanged by this lab (still revision 2, one load balancer, desired 2)

**Only reasoned about (not available on Floci):**
- the service-linked role and its path
- registering and re-registering a scalable target, and the floor raising desiredCount
- the two TargetTracking- alarms AWS creates, and their 3 vs 15 evaluation periods
- an alarm changing state by itself because the metric moved (it stayed INSUFFICIENT_DATA)
- a policy firing, a scaling activity, and its Cause string
- cooldowns, DisableScaleIn, the target tracking calculation
- scheduled actions firing, time zones
- suspension actually stopping scaling
- the cost

---

## Review Questions

### Q1. The nine lines, and what auto scaling changes about my application

The nine lines are listed above. This lab is responsible for three of them: the metric and alarm noticing the load (line 2), the alarm invoking a policy (line 3), and the policy writing desiredCount within the bounds of 2 to 10 (line 4). The other six didn't need any change because they were already built to react to desiredCount by themselves. In Lab 04 the ECS service was set up so its only job is to make runningCount match desiredCount, so it starts a task from the same task definition whenever the number goes up. Lab 02's private subnets give each new task an address, the security group from Lab 05 already lets the load balancer reach any task carrying that group, and the service registers each new task in the target group on its own. None of those parts care who changed the number, a person or a policy, so nothing about them had to be touched. If someone asks what auto scaling changes about my application, my answer is: nothing, it only changes how many copies of it are running.

### Q2. Why the full ARN fails as a resource ID

The resource ID for an ECS service is not an ARN. It's a short path, `service/<cluster>/<service>`, which happens to be exactly the end part of the service's ARN (everything after the last colon). Application Auto Scaling works with nine different services, and each one names its resources differently, so instead of taking ARNs it uses a path format per namespace: `service/usms-ecs-cluster/usms-enrolment-svc` for ECS, `table/<table-name>` for DynamoDB, and `function:<name>:<alias>` for Lambda. Passing the whole ARN fails because it doesn't match the ECS path format, and the error doesn't say "you gave it too much". The other three constructed identifiers in this architecture are: the ECS control-plane names `--cluster usms-ecs-cluster --service usms-enrolment-svc` (from the service), the full service ARN used for ECS tagging, and the ResourceLabel `app/<alb>/<id>/targetgroup/<tg>/<id>`, built from the end of the load balancer's ARN and the end of the target group's ARN.

### Q3. Registering a floor above the current count

The **scalable target** made the change. When its MinCapacity is above the current desiredCount, Application Auto Scaling raises desiredCount to the floor straight away. This differs from a scaling policy because no alarm fired and no metric was involved: it's just the bounds being enforced, and it happens even if there are no policies at all. A realistic 3am incident: the service is overloaded and the on-call engineer re-registers the target with a minimum of 5 to get more tasks quickly, then goes back to bed. The evidence left for the person who takes over at 8 is the MinCapacity of 5 in `describe-scalable-targets` (and no matching policy activity explaining the extra tasks), a scaling activity if it was recorded, and, on real AWS, a CloudTrail entry showing who called `register-scalable-target` and when.

### Q4. The alarms AWS made vs the one I made

The two target tracking alarms belong to the policy. AWS creates them, rebuilds them whenever the policy changes, and deletes them when the policy is deleted. If I edit one, my change gets overwritten without warning. If I delete one, the policy silently stops scaling in one direction, and nothing tells me. The queue alarm belongs to me: I created it, nothing changes it behind my back, and I have to delete it myself. The big thing mine can do that theirs can't is have more than one action, so it could scale the service *and* send an SNS notification to wake someone up. I'd argue for `breaching` as the missing-data setting for the queue alarm, because if the app stops publishing queue depth, that's much more likely a problem with the app than an empty queue. If I'm right and the app has crashed, treating missing data as breaching would add tasks that can't fix a crashed app, so it costs money, but at least the alarm goes off and someone notices.

### Q5. Why reactive scaling can't absorb the first minutes

Before any new task can serve a request, several delays have to pass one after another: the metric has to be published and the alarm has to see it above the threshold for its evaluation periods (3 × 60 s for target tracking, set by AWS), the policy is invoked (a few seconds), ECS has to start the Fargate task (20–60 s), and the load balancer waits through the grace period (60 s, set on the service in Lab 05). That's about 5 minutes, and during all of it the only capacity serving students is what was already running. It isn't a bug, it's just how long those steps take. The three consequences are:
- **The minimum capacity is really a latency decision,** because it's what takes the first minutes of any spike. This justifies the floor of 2.
- **Scaling out should be fast and scaling in slow.** This justifies the 60 s scale-out cooldown vs 300 s scale-in.
- **For a spike you know about in advance, reactive scaling is the wrong tool.** This justifies the scheduled actions that raise the floor at 07:45, before enrolment opens.

### Q6. Two target tracking policies that disagree

When the CPU policy and the request-count policy disagree, scaling out uses whichever asks for the **most** tasks, and scaling in only happens when **every** policy agrees it's safe. The rule is lopsided on purpose: if any signal says "we need more", it's safer to add capacity, but you should only remove capacity when all signals agree it isn't needed. Two target tracking policies on the **same** metric with different targets are a fault, not a backup, because they're like two thermostats in one room set to different temperatures. One keeps adding tasks to reach its target, the other keeps removing them to reach its own, and the service goes up and down. A step policy and a target tracking policy on the same metric is the same mistake in a different form: target tracking calculates the number of tasks to hit its target, while the step policy adds fixed amounts at its own threshold, so they keep undoing each other's work.

### Q7. Why requests per target beats CPU

Three reasons:
- **CPU depends on the task size I chose.** The same load shows 80% on a 256 CPU task but 20% on a 1024 CPU task, so resizing a task silently changes how the CPU policy behaves. Requests per target means the same thing whatever the task size.
- **Request count moves the moment students start clicking,** while CPU only goes up once the work has started. For an app that mostly waits on the database, CPU might barely move at all.
- **Requests per target is a number the business understands,** like "1200 registrations at once", while a CPU percentage doesn't translate into anything.

CPU is the better choice for work that is genuinely CPU-heavy and very uneven per request, like generating PDF transcripts, where one request can cost a hundred times more than another, so counting requests says little about the real load. Requests per target would scale the enrolment app badly if its requests were very uneven, for example if some registrations took seconds because they waited on a slow database while others were instant. Then a task could be overloaded by a few slow requests while the request count still looks low. The ALB's **TargetResponseTime** metric would have shown that before choosing it, because response times would climb while the request count stayed flat.