# Lab 05 Notes

**Floci support path: B - control plane, with a partial data path.**

- `describe-load-balancers`, `describe-target-groups` and the ELBv2 skeletons all answered.
- `describe-listeners` with the fake ARN `probe` returned an empty list (`"Listeners": []`) instead of a ValidationError, so Floci doesn't validate ARN format.
- The load balancer, target group, listener and rules are all created, stored and survive a restart.
- The ECS service registers and removes its own targets, and Floci really runs the target group health check (targets went `initial` -> `healthy`).
- But the ALB DNS name (`usms-enrolment-alb-a152a9ed117a4a9b.elb.floci`) doesn't resolve and curl got `http_code=000`, so no request could go through the load balancer from my machine.

---

## Your-turn answers

**Step 4 (port 443):** Opening 443 on the security group doesn't make HTTPS work, because two things are still missing: an HTTPS listener on port 443 (the firewall rule only opens the port, nothing is listening on it) and a TLS certificate for that listener. AWS Certificate Manager gives the certificate for free, but you need a domain name from outside to prove you own it.

**Step 6 (matcher):**
- (a) An app that redirects `/` to `/login` (returns a 302) would be marked unhealthy forever with the strict `200` matcher, even though it works fine.
- (b) It would be a bug in my work, not in the script. The verify script records the decision that was made (strict 200), and its job is to catch the setup drifting away from that decision.

**Step 11 (desired 3 and back):** If the service didn't register its own targets, I would have to run `register-targets` with each new task's IP (and `deregister-targets` for the ones that stopped) by hand after every single scaling event.

---

## ECS health vs target health (Step 11)

| ECS healthStatus | Target health | What it means |
|---|---|---|
| HEALTHY | healthy | Working |
| HEALTHY | unhealthy | The network path is broken: security group, subnet, or the health check path/matcher |
| UNHEALTHY | unhealthy | The application itself is broken, so read the container logs |
| UNKNOWN | healthy | Not a fault, the task definition has no container health check |
| anything | unused | Nothing forwards to this target group |

On my build ECS showed `None` for every task (not even `UNKNOWN`) and the target group showed `healthy`. My revision 2 has no container health check, so the closest row is "UNKNOWN + healthy = not a fault". Floci just doesn't fill in the field at all.

---

## Section 12.1 for my build

**Observed (I actually saw it happen):**
- a security group that admits 0.0.0.0/0 on purpose, with nothing behind it that does
- the load balancer created across two subnets in two AZs
- a load balancer with no listener, and then the target group's attached count going 0 -> 1 once the listener existed
- the target group created as `ip`
- the ECS service attached to a target group (after recreating it) and registering targets without me running `register-targets`
- targets going from `initial` to `healthy`, so health checks really ran (this moved up from "conceptual")
- a third target appearing when I scaled to 3, and one disappearing when I scaled back to 2
- a listener rule at priority 10 listed ahead of the default action
- everything surviving a Floci restart, with every ARN re-derived from the API

**Observed, but different from the lab:**
- target addresses were Docker IPs (172.27.0.x), not inside Lab 02's private subnet CIDRs
- the forced deployment produced the same task ARNs and IPs, not new ones
- the cutover: the revoke returned `True`, but the old rule was still listed, and Lab 04's check had already been failing since Lab 4, so the expected one-line change never showed up

**Only reasoned about (did not see):**
- a request going from a client to a task and back (curl got 000)
- a target `draining` while in-flight requests finish
- least_outstanding_requests actually choosing a target
- the /alb-health rule being matched against a real URL
- the 2-4 minute provisioning time (Floci was active instantly)
- security groups actually blocking or allowing packets (Floci doesn't enforce them)
- HTTPS and certificates
- the cost

---

## Review Questions

### Q1. What the group-referenced rule and the load balancer have in common

Both of them solve the same problem: the tasks don't have stable addresses, so nothing should depend on a task's IP. In Lab 04 the security group rule pointed at a group (`usms-app-sg`) instead of an IP range, so it stayed correct no matter which IPs the web servers or tasks had. In this lab the load balancer does the same thing for clients: the portal calls one fixed DNS name, and the target group keeps the list of real task IPs up to date. In both cases something else (the security group membership, or the ECS service registering targets) keeps the list of addresses correct, so I never have to type one. The general problem is "giving a stable name to things that keep changing". A third solution to the same problem is DNS itself, where a hostname stays the same while the IP behind it changes. Service discovery tools like AWS Cloud Map or Kubernetes Services are another example.

### Q2. "The health check says unhealthy, so the app is broken"

That's not a safe conclusion. The target group health check runs from outside, across the network, so it fails in two different situations: when the application really is broken, and when the application is fine but the load balancer can't reach it (for example the security group doesn't allow `usms-alb-sg`, or the health check path or matcher is wrong). The target group alone can't tell these apart. The field that tells them apart is the ECS `healthStatus` from the container health check, which runs inside the task. The sequence I'd follow is: check ECS `healthStatus` first. If it's HEALTHY, the app is fine and the problem is the path, so I'd check the task security group allows `usms-alb-sg` on port 80, then the health check path and matcher. If ECS also says UNHEALTHY, then the app is broken and I'd read the container logs.

### Q3. Why there's no update-target-group-target-type

It shows that AWS treats the target type as part of what the target group *is*, not just a setting on it. If you want a different target type, you need a different target group. This is the same idea as Lab 04's task definition revisions, which can never be edited, only replaced with a new revision. Two other fields in this lab that work the same way are the target group's **VPC** (a target group belongs to one VPC forever) and the load balancer's **scheme** (internet-facing or internal), which also can't be changed after creation (the ALB's **type** is another one). A field that looks like it should be fixed but isn't is the **health check settings**, including the matcher, which I changed to `200-399` and back without recreating anything. The ALB's security groups can also be changed later with `set-security-groups`.

### Q4. A request that arrives just as its task is being stopped

When ECS decides to stop a task (because of a deployment, a scale-in or a failed health check), it first deregisters the task from `usms-enrolment-tg`. The load balancer marks the target as `draining`: it sends it no new requests, but lets requests already in flight finish. It waits up to **deregistration_delay.timeout_seconds** (30 seconds, set on the target group in Step 7). After that, ECS sends SIGTERM to the container and waits **stopTimeout** (set in the task definition) for it to shut down cleanly, then sends SIGKILL. Meanwhile, **minimumHealthyPercent** (set on the service) makes sure enough other tasks are still running to handle new requests. So if the request finishes within 30 seconds, it succeeds, and new requests go to the other healthy tasks. If the delay were left at the default of 300 seconds, each task would wait up to 5 minutes before stopping, so a deployment of two tasks could take around 10 minutes, even though the enrolment requests finish in milliseconds.

### Q5. Should Lab 04's script be updated or left failing?

The case for updating it straight away is that the change was planned, and a verification script should describe the system as it really is now. If it stays red, people stop trusting it, and a real failure later could be ignored as "the usual one". The case for leaving it failing and documented is that Lab 04's script is a record of what Lab 04 built, and the failure itself shows clearly that the architecture changed in Lab 05. On a system with four other engineers, I would update it in the same commit as the change, with a message explaining why. Otherwise someone else will see a red check, not know it's expected, and waste time on it, or worse, "fix" it by putting the old rule back. On a system with only me, leaving it failing with a note is more acceptable, because I already know why it's red, although updating it is still cleaner.

### Q6. An internet-facing ALB in front of tasks with no public address

Both can be true because the load balancer and the tasks are in different subnets with different routes. The ALB nodes sit in `usms-public-subnet-a` and `-b`, which use `usms-public-rt` with a route to `usms-igw`, so the internet can reach the ALB. The tasks sit in `usms-private-subnet-a` and `-b`, which use `usms-private-rt` with no route to the internet gateway, only to `usms-nat` for outbound traffic. The ALB receives the request, then opens a brand-new connection to the task's private IP inside the VPC, so the tasks never need a public address. If an attacker took over the load balancer's configuration, they could only send traffic where a listener can forward it, and the task security group only allows port 80 from `usms-alb-sg`. They could reach the enrolment tasks on port 80, but not the database, not other ports, and not anything that doesn't trust `usms-alb-sg`. If the tasks had public addresses instead, anyone on the internet could try to connect to them directly and skip the load balancer completely, including its rules and health checks.

### Q7. Why requests per target is a better scaling signal than CPU

For a web API, the thing that actually puts load on the service is the number of requests coming in, and request count goes up the moment more students start clicking, before CPU has time to climb. It also matches what the user actually feels. CPU is the better signal when each request does heavy CPU work, for example generating PDF transcripts or reports, where a small number of requests can max out the CPU. `ALBRequestCountPerTarget` would scale the enrolment service badly if requests were very uneven, for example if some requests were tiny and others took seconds because they waited on the database. Then a task could be overloaded with only a few slow requests, and request count would stay low while users are already waiting.
