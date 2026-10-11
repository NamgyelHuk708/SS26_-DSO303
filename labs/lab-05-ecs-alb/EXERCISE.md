# Lab 5 Independent Exercises

---

## Exercise 1: A Second Path Through the Same Load Balancer

### What I did
I created a second target group, `usms-results-tg`, for the future results service, and a rule at priority 20 that sends `/results` and `/results/*` to it.

- Target group: same target type (`ip`), protocol and port as `usms-enrolment-tg`, health check on `/`, matcher `200-399`, deregistration delay 15 seconds
- Tags on both: `Project=USMS`, `Tier=app`, `Lab=05`, `Service=results`
- The rule's conditions and actions are JSON files in `templates/` (`lab-05-ex1-rule-conditions.json` and `lab-05-ex1-rule-actions.json`), not the inline shorthand
- Every ARN was captured with `$(...)` and `--query`
- I didn't create a second ECS service and didn't register any targets, so the target group stays empty on purpose
- Neither object went into `configs/lab-05.env`, because Exercise 4 removes them

```bash
RESULTS_TG_ARN=$(aws elbv2 create-target-group \
  --name usms-results-tg --protocol HTTP --port 80 \
  --vpc-id "$USMS_VPC_ID" --target-type ip \
  --health-check-protocol HTTP --health-check-path / --health-check-port traffic-port \
  --matcher HttpCode=200-399 \
  --tags Key=Name,Value=usms-results-tg Key=Project,Value=USMS Key=Tier,Value=app Key=Lab,Value=05 Key=Service,Value=results \
  --query 'TargetGroups[0].TargetGroupArn' --output text)

aws elbv2 modify-target-group-attributes --target-group-arn "$RESULTS_TG_ARN" \
  --attributes Key=deregistration_delay.timeout_seconds,Value=15
```

![Exercise 1 - target group and rule created](LAB_05(image)/ex1.1.png)

### Verification
`describe-rules` doesn't always return rules in priority order, and `Priority` is a string with the default action written as the word `default`. So I sorted them with `jq`, turning `default` into 99999 so it always comes last:

```bash
aws elbv2 describe-rules --listener-arn "$USMS_ALB_LISTENER_ARN" --output json \
  | jq -r '.Rules | sort_by(if .Priority=="default" then 99999 else (.Priority|tonumber) end)[] | ...'
```

| Priority | Action | Paths |
|---|---|---|
| 10 | fixed-response | /alb-health, /alb-health/* |
| 20 | forward | /results, /results/* |
| default | forward | (everything else) |

The results target group showed `TargetHealthDescriptions: []`, `LBs: 1` and `Matcher: 200-399`.

![Exercise 1 - rules in order and empty target group](LAB_05(image)/ex1.2.png)

### What would a request to /results get?
It would get an **HTTP 503 Service Unavailable** from the load balancer itself. The rule matches and forwards to `usms-results-tg`, but that group has no targets, so there is nowhere to send the request.

---

## Exercise 2: Repairing the Verification Script

### The property the old check was testing
The enrolment tasks only accept traffic from a named security group, never from an IP range. `IpPermissions[0].UserIdGroupPairs[0].GroupId == usms-app-sg` was just one way of writing that property, tied to the architecture before Lab 05.

### What I changed in `scripts/utilities/verify-lab-04.sh`
1. Added `source configs/lab-05.env 2>/dev/null || true`, so the script still runs for someone who did Lab 04 but not Lab 05.
2. Added `: "${USMS_ALB_SG:=none}"`, so `set -u` can't crash the script before it prints anything. If the variable is missing, the check just fails with a readable name.
3. **Changed** the old check (didn't delete it). It now asserts the source group is `usms-alb-sg`, and it searches all source groups instead of only the first one, because AWS merges several sources on the same port into one entry.
4. **Added** a check that `usms-app-sg` is no longer a source. Without it, a group that allowed both the old and the new source would still pass.
5. Wrote the expected count in a comment at the top.

```bash
check "usms-enrolment-sg is sourced from a group (usms-alb-sg after Lab 05), not a CIDR" \
  "test \"$USMS_ALB_SG\" != none && enrolsrc | grep -qw $USMS_ALB_SG"
check "usms-app-sg is no longer a direct source of usms-enrolment-sg" \
  "! enrolsrc | grep -qw $USMS_APP_SG"
```

The script still works from any directory, because I didn't touch the `${BASH_SOURCE[0]}` line.

### Result
| Script | Result |
|---|---|
| verify-lab-04.sh | PASS=38 FAIL=1 |
| verify-lab-05.sh | PASS=45 FAIL=4 (unchanged) |

![Exercise 2 - both verify scripts after the change](LAB_05(image)/ex2.png)

The exercise expects FAIL=0 from both, but that can't happen on my Floci. The new "sourced from usms-alb-sg" check fails because Floci never stores the source group of a group-referenced rule. The check itself is correct, and on real AWS the count would be **PASS=39 FAIL=0** (one check became two). The "usms-app-sg is no longer a source" check passes.

I committed it with a message that says why the check changed:

```
verify-lab-04: assert the enrolment tasks are reachable only via the load balancer's security group, because Lab 05 moved their caller from the web tier to the ALB
```

### Why write the count down
If the expected PASS number isn't written anywhere, a check that got deleted or stopped running looks exactly the same as a clean run. A documented count means a missing check gets noticed.

### When to update a verification script
It's right to update a verification script when the architecture was changed on purpose. Do it in the same commit as the change, so the script keeps describing the system as it really is. Changing a check just to make a red result go away, when nothing was meant to change, is how a real regression gets hidden.

---

## Exercise 3: A Load Balancer Report Tool

### What I did
I wrote `scripts/utilities/usms-lb-report.sh`. With no arguments, it finds every ALB whose name starts with `usms-` and prints its full routing table: load balancer, listeners, rules in evaluation order, and the target counts for each forward action. It also writes the same data to `outputs/lab-05-lb-report.json`.

How it works:
- **The shell** makes the AWS calls, four levels deep: load balancers → listeners → rules → target health.
- **Python** does the sorting and formatting, because nested JSON is much easier to handle there than in bash.
- **Nothing is hard-coded** except the `usms-` prefix. It finds everything else itself.
- **Sorting:** `Priority` is a string and the default action's priority is the word `default`. A plain sort would put it in the wrong place, so the script maps `default` to a very large number and the other priorities to integers. That way the default action is always printed last, which is when it's actually evaluated.
- **Non-forward actions** print their own summary (for example `fixed-response 200`), not an empty target group column.
- **Edge cases:** a load balancer with no listeners prints `(no listeners)`, and an empty target group prints `0 targets, 0 healthy`, not a blank line.

### About `set -e`
I used `set -uo pipefail` without `-e`. A load balancer with no listeners or an empty target group makes some calls return nothing or fail, and with `-e` one odd object would stop the whole report. It's better to print "none" for that object and keep going. This is in a comment at the top of the script.

### Verification
It gave the same output from my home folder and from the repo folder:

```
usms-enrolment-alb   internet-facing  application  active   AZs=2  SGs=1
  HTTP:80
    prio  10       path-pattern  /alb-health,/alb-health/*    -> fixed-response 200
    prio  20       path-pattern  /results,/results/*          -> usms-results-tg  (0 targets, 0 healthy)
    prio  default  -                                          -> usms-enrolment-tg  (3 targets, 2 healthy)
```

![Exercise 3 - syntax check](LAB_05(image)/ex3.1.png)

![Exercise 3 - run from home and from the repo folder](LAB_05(image)/ex3.2.png)

After Exercise 4 deleted the priority-20 rule, I ran it again. It still worked and just showed one rule fewer:

![Exercise 3 - after the results rule was removed](LAB_05(image)/ex3.3.png)

### Something I noticed
The enrolment target group showed **3 targets, 2 healthy**, even though the service's desired count was 2. The third entry is a leftover from my Step 11 test where I scaled to 3 and back. On real AWS, the removed task would be `draining` for 30 seconds and then disappear. On Floci, an old target sometimes stays in the list. The report correctly shows only 2 as healthy, so the tool did its job: it reported what was really in the target group instead of assuming it matched the service.

---

## Exercise 4: The Exposure Review

### What changed (two sentences)
1. **Network path:** before this lab, the enrolment tasks could only be reached directly from `usms-web-01` inside the VPC. Now an internet-facing load balancer in the public subnets forwards HTTP requests from the internet to them.
2. **Security groups:** `usms-alb-sg` now allows port 80 (and 443) from `0.0.0.0/0`, and `usms-enrolment-sg` is meant to allow port 80 only from `usms-alb-sg` instead of from `usms-app-sg`.

### Internal or internet-facing?
With `--scheme internal`, Step 5's command would use the **private** subnets instead of the public ones, and the ALB's DNS name would resolve to private IPs that only things inside the VPC can reach. The listener, target group, rules, the service attachment and the task security group would all stay exactly the same.

**My recommendation for USMS enrolment is internal.** The portal (`usms-web-01`) is the only known client and it's already inside the VPC, so there's no reason to give the enrolment API a public address at all.

**The other side:** an internet-facing ALB makes sense if the students' browsers or a mobile app should call the enrolment API directly, or if the portal ever moves outside this VPC. It also gives one public HTTPS entry point where you could add protection like a web application firewall.

### Exposure, before and after

| | Before Lab 05 | After Lab 05 |
|---|---|---|
| What can reach the load balancer | There was no load balancer | Anyone on the internet, on port 80 (443 is open but nothing listens) |
| What can reach the tasks | `usms-web-01` (anything carrying `usms-app-sg`) | Only the load balancer (`usms-alb-sg`) |
| What can reach the tasks **directly** | `usms-web-01` | Nothing. The direct rule from the web tier was removed in Step 13 |

On my Floci build, security groups aren't enforced at all, and the revoke in Step 13 returned `True` while the old rule was still listed. So the table above describes the design as configured, which is what real AWS would enforce.

### Monthly cost
Prices for us-east-1 from the Elastic Load Balancing pricing page (https://aws.amazon.com/elasticloadbalancing/pricing/):
- **$0.0225 per ALB-hour**
- **$0.008 per LCU-hour**

One LCU is measured on four things, and you pay for whichever is highest: 25 new connections per second, 3,000 active connections per minute, 1 GB processed per hour (for container targets), or 1,000 rule evaluations per second.

**Idle:** $0.0225 × 730 hours = **$16.43 per month**, even if nothing ever uses it.

**Under load** (my assumptions: enrolment week peak of 50 requests per second for 2 hours, about 10 KB per response, 2 rules):

| LCU dimension | Working | LCUs |
|---|---|---|
| New connections | 50 ÷ 25 | **2.0** |
| Processed bytes | 50 × 10 KB × 3,600 s ≈ 1.8 GB/hour | 1.8 |
| Rule evaluations | only 2 rules, well under the 10 free | ~0 |

New connections is the biggest one at peak, so it's 2 LCU × $0.008 × 2 hours ≈ **$0.03**.

For the rest of the month at about 1 request per second, it's roughly 0.04 LCU × 728 hours × $0.008 ≈ **$0.23**.

**ALB total ≈ $16.70 per month.** Almost all of it is the fixed hourly charge, which is why an idle load balancer is a classic surprise on an AWS bill.

**For comparison,** the two Fargate tasks behind it (0.25 vCPU and 1 GB each since Lab 04 Exercise 2) cost about 2 × $10.63 = **$21.26 per month**, using $0.04048 per vCPU-hour and $0.004445 per GB-hour from https://aws.amazon.com/fargate/pricing/.

### HTTPS plan
Opening port 443 on `usms-alb-sg` (the Step 4 "Your turn") only opens the firewall. Nothing is listening on that port yet. To get working HTTPS:

1. **A domain name** for the API (for example `enrol.usms.cst.edu.bt`). This comes from outside AWS (the college's DNS), or you can buy one in Route 53.
2. **A public certificate from AWS Certificate Manager (ACM).** Public ACM certificates are **free**. (https://docs.aws.amazon.com/acm/latest/userguide/gs-acm-request-public.html)
3. **DNS validation:** ACM gives you a CNAME record to add to the domain's DNS, to prove you own the domain. This step needs access to that DNS, which is outside AWS here.
4. **A DNS record** (a CNAME, or a Route 53 alias) pointing the domain at the ALB's DNS name.
5. **An HTTPS:443 listener** on the ALB using the ACM certificate and a TLS security policy, forwarding to `usms-enrolment-tg`. This is what actually makes something listen on 443.
6. **The security group rule for 443.** Already done in Step 4.
7. **Change the port 80 listener's default action to a `redirect`** action (HTTP 301 to HTTPS on 443), so no login ever goes over plain text.

So AWS provides the certificate and the listener for free (you only pay for the ALB itself), but the domain and its DNS records have to come from somewhere outside.

### The tidy-up
I removed the two practice objects from Exercise 1, the rule first and then the target group, because a target group can't be deleted while a rule still forwards to it.

> **What will be deleted:** the priority-20 listener rule that forwards /results to usms-results-tg.
> **What depends on it:** nothing — no service uses /results yet.
> **Reversible?** Yes — it can be recreated with the Exercise 1 command.
> **Effect on later labs:** none. The /alb-health rule at priority 10 is not touched.

```bash
RESULTS_RULE_ARN=$(aws elbv2 describe-rules --listener-arn "$USMS_ALB_LISTENER_ARN" \
  --query "Rules[?Priority=='20'].RuleArn | [0]" --output text)
aws elbv2 delete-rule --rule-arn "$RESULTS_RULE_ARN"
```

> **What will be deleted:** the target group usms-results-tg (empty, from Exercise 1).
> **What depends on it:** nothing once the rule above is gone.
> **Reversible?** Yes — it can be recreated with the Exercise 1 command.
> **Effect on later labs:** none. usms-enrolment-tg, which Lab 06 needs, is not touched.

```bash
RESULTS_TG_ARN=$(aws elbv2 describe-target-groups --names usms-results-tg \
  --query 'TargetGroups[0].TargetGroupArn' --output text)
aws elbv2 delete-target-group --target-group-arn "$RESULTS_TG_ARN"
```

### Verification
Afterwards the listener had only rule `10 fixed-response` and `default forward`, and `usms-enrolment-tg` was the only target group left.

![Exercise 4 - rule and target group deleted](LAB_05(image)/ex4.1.png)

The exercise asks for `verify-lab-05.sh` to report FAIL=0 afterwards. It gave **PASS=45 FAIL=4**, exactly the same as before the deletion. The four failures are the Floci limitations already documented in the report (group-referenced rule not stored, grace period null, deployments null, and the `None` this leaves in `lab-05.env`), so the tidy-up didn't break anything I needed to keep.

![Exercise 4 - verify after the tidy-up](LAB_05(image)/ex4.2.png)

---

## Exercise 5: The ResourceLabel Hand-Off to Lab 06

### The script
I wrote `scripts/utilities/usms-resource-label.sh`. It takes a load balancer name and a target group name (defaulting to this lab's two), looks up both ARNs from the API, and builds:

```
app/usms-enrolment-alb/a152a9ed117a4a9b/targetgroup/usms-enrolment-tg/1210fc467d47436e
```

It doesn't read `configs/lab-05.env` for the ARNs, because a script that reads the answer from a file it helped write doesn't prove anything.

**Why the two suffixes need different treatment:**
- The load balancer ARN ends in `:loadbalancer/app/NAME/ID`, but the label only wants `app/NAME/ID`, so the word `loadbalancer/` has to be **cut off**: `${LB_ARN#*:loadbalancer/}`
- The target group ARN ends in `:targetgroup/NAME/ID`, and the label wants `targetgroup/NAME/ID`, so the word `targetgroup/` has to be **kept**. Stripping everything up to the last colon does that: `${TG_ARN##*:}`

Both use shell parameter expansion, not `awk`. Before printing, the script checks the label has 6 segments, starts with `app`, has `targetgroup` in position 4 and contains both names. If not, it exits with an error.

### Added to lab-05.env
I appended `USMS_ALB_RESOURCE_LABEL` to `configs/lab-05.env` using the script's output, not by typing it. The export count went from 15 to **16**. The empty-value check still only shows the known `USMS_SVC_GRACE_PERIOD=None` line.

### Checking the label
| Check | Result |
|---|---|
| Segments | 6 |
| First segment | `app` |
| Contains the ALB name | yes |
| Contains the target group name | yes |

`app` is there because it's the load balancer type taken from its ARN (application). For a Network Load Balancer it would be `net`.

![Exercise 5 - script, label and checks](LAB_05(image)/ex5.1.png)

### Measuring a capacity replacement
I recorded a UTC start time with `python3`, forced a new deployment, and polled until the service was back at its desired count with a different task list. Floci never replaced the tasks: every poll said `changed=no`. I stopped waiting after **106.7 seconds**, so that number doesn't mean anything.

AWS documents Fargate task start-up as roughly 20 to 60 seconds. Behind this load balancer, replacing two tasks one at a time would mean each new task starts, passes 2 health checks 30 seconds apart, and then the old task drains for up to 30 seconds. So a full replacement would take a few minutes, and Lab 06's cooldowns should be sized on that, not on Floci.

![Exercise 5 - timing attempt](LAB_05(image)/ex5.2.png)

### Readiness file
`outputs/lab-05-lab04c-readiness.txt` (copied to `labs/lab-05-ecs-alb/` so it can be committed) has:

| Item | Value |
|---|---|
| ResourceLabel | `app/usms-enrolment-alb/a152a9ed117a4a9b/targetgroup/usms-enrolment-tg/1210fc467d47436e` |
| Target group ARN | `...:targetgroup/usms-enrolment-tg/1210fc467d47436e` |
| Load balancer ARN | `...:loadbalancer/app/usms-enrolment-alb/a152a9ed117a4a9b` |
| Scalable resource ID | `service/usms-ecs-cluster/usms-enrolment-svc` |
| Scalable dimension | `ecs:service:DesiredCount` |
| Current desired count | 2 |
| Capacity replacement | not meaningful on Floci (see above) |

**Recommended metric for Lab 06: `ALBRequestCountPerTarget`.** The enrolment API is a web API, so the number of requests each task handles is what actually overloads it, and that number goes up before CPU does. On this build the CPU metrics also have no data, because Container Insights wasn't recorded on the cluster in Lab 04.

![Exercise 5 - readiness file](LAB_05(image)/ex5.3.png)

---

## Summary

| Exercise | Result |
|---|---|
| 1 | Second target group and a priority-20 rule for /results; rules read back in the correct order |
| 2 | verify-lab-04.sh now checks for usms-alb-sg and that usms-app-sg is gone; 38/1 on Floci, 39/0 expected on real AWS |
| 3 | A report tool that prints the routing table for every usms-* ALB, from any folder, with the default action last |
| 4 | Recommended an internal ALB, ALB cost ≈ $16.70/month (almost all fixed), HTTPS plan with a free ACM certificate, and the practice objects removed |
| 5 | ResourceLabel built from the API and saved for Lab 06; the timing test showed Floci doesn't replace tasks |

The Floci problems in these exercises were the same ones as in the main lab: group sources not stored, tasks not replaced on a forced deployment, and old targets sometimes staying in the target group. For each one I wrote down what real AWS would have done.