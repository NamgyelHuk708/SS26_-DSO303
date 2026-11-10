# Lab 8 Independent Exercises

---

## Exercise 1: A Second Autoscaler (usms-results)

### What I did
I wrote `manifests/lab-08/11-hpa-results.yaml` (`autoscaling/v2`, not `kubectl autoscale`): target `usms-results`, **min 2, max 6, 60 % CPU**, scale-up at most **2 pods every 30 s**, and a **180 s** scale-in stabilisation window. I first checked that usms-results declares a CPU request (`{"cpu":"50m","memory":"32Mi"}`), then passed a client-side dry run before applying it.

### Result
`kubectl get hpa` shows two autoscalers reporting percentages:

| HPA | Target | Min / Max | Replicas |
|---|---|---|---|
| usms-enrolment-hpa | cpu 2 % / 50 % | 2 / 8 | 2 |
| usms-results-hpa | cpu 2 % / 60 % | 2 / 6 | 2 |

`describe` confirms Scale Up `Pods 2 per 30 s` and Scale Down window 180 s. Because I only set the window, Kubernetes filled in its default scale-down policy (`Percent 100 / 15 s`), so after the window results could drop straight to its minimum – unlike enrolment's 1 pod per minute.

**Why 60 % for results:** results is read-mostly, with steady requests of similar cost, so its pods can safely run hotter before adding more; enrolment's traffic is spiky (everyone registers at once), so it needs more headroom while new pods start.

![Exercise 1](LAB_08(image)/ex1.png)

---

## Exercise 2: Make the Gateway Drainable

### The problem
`usms-gateway-pdb` is `minAvailable: 1` on a **single-replica** Deployment, so ALLOWED DISRUPTIONS was **0** – no voluntary eviction or drain could ever move it.

### The fix – without weakening the PDB
Run **two gateway replicas**. I changed `replicas: 1 → 2` in `manifests/lab-07/40-gateway.yaml` and checked with `kubectl diff` before applying.

### What `kubectl diff` caught
The diff showed two changes, not one: the Deployment's replicas **and** the gateway Service going back from **LoadBalancer to ClusterIP** (losing the nodePort, the AWS annotations and the external IP). Two files described the same Service – Lab 07's `40-gateway.yaml` and Lab 08's `50-service-loadbalancer.yaml` – and whichever is applied last wins.

![Exercise 2 - the diff that caught the Service revert](LAB_08(image)/ex2.1.png)

I removed the Service from `40-gateway.yaml` so `50-service-loadbalancer.yaml` is its only source. The diff then showed only `replicas: 1 → 2`. After applying:

| Check | Result |
|---|---|
| Gateway Service | still LoadBalancer, 172.17.0.3, nodePort 30192 |
| `usms-gateway-pdb` | MIN AVAILABLE 1, **ALLOWED DISRUPTIONS 1** (was 0) |
| Pods | 2 gateway pods, both on node `i-acfd2de022a9365b8.ec2.internal` |
| `kubectl diff -f manifests/lab-07/40-gateway.yaml` | **clean** – the repository matches the cluster |

![Exercise 2 - fix applied](LAB_08(image)/ex2.2.png)

### Proof it is drainable
The same eviction call that Step 12 refused now returned `"status":"Success","code":201`. The gateway kept answering from the other pod, a replacement started, and ALLOWED returned to 1.

![Exercise 2 - eviction allowed while serving](LAB_08(image)/ex2.3.png)

### Spreading across nodes
My cluster has **one node**, so I cannot show the two pods on different nodes. On a multi-node cluster I would add `topologySpreadConstraints` (or `podAntiAffinity`) on `kubernetes.io/hostname`, as I did for enrolment in Lab 07 Exercise 4, so a node drain never takes both gateways.

---

## Exercise 3: The Autoscaler That Will Not Act

### Applied exactly as given, then diagnosed with commands

| # | Command | What it showed |
|---|---|---|
| 1 | `kubectl get hpa usms-reports-hpa` | `cpu: 0%/70%`, MIN 4, MAX 4, REPLICAS 4 |
| 2 | `kubectl describe hpa` (Conditions, Events) | `New size: 4; reason: Current number of replicas below Spec.MinReplicas`; ScalingLimited True `TooFewReplicas` |
| 3 | pod QoS and resources | **Guaranteed, CPUREQ 200m = CPULIM 200m** – although the manifest set no request |
| 4 | `jsonpath min/max` | **min=4 max=4** |

![Exercise 3 - diagnosis](LAB_08(image)/ex3.1.png)

### The two faults
- **Fault 1 – the metric fault (the lab's `<unknown>` case).** The container sets limits but **no requests**. On this Kubernetes (k3s v1.30), the API server **defaults requests to the limits**, so the HPA did **not** show `<unknown>`: it computed against **200m**. It "works", but against the wrong denominator – 70 % of 200m = 140m per pod, roughly four times later than the 50m request my other services use – and every pod reserves 200m of the node's ~2 CPUs. On a cluster that does not default requests, the same omission gives `<unknown>` and `missing request for cpu`. (The two `FailedGetResourceMetric` warnings at 53 s were only the first seconds before the new pods had metrics.)
- **Fault 2 – prevents action even with perfect metrics.** `minReplicas 4 = maxReplicas 4`: the clamp leaves exactly one possible value. The HPA forced the Deployment from 2 to 4 and could never change it again.

### The fixes – one field each
1. `requests.cpu: 50m` on the container → pods **Burstable 50m / 200m**.
2. `maxReplicas: 8` on the HPA → room to move between 4 and 8.

Right after fix 1 replaced every pod, the HPA briefly showed `<unknown>` (no metrics yet for brand-new pods). Re-run with a 90 s wait, it reported **`cpu: 0%/70%`, MIN 4 / MAX 8, ScalingActive True (ValidMetricFound)**.

![Exercise 3 - fixes](LAB_08(image)/ex3.2.png)

![Exercise 3 - redo with a real percentage](LAB_08(image)/ex3.3.png)

`usms-reports` and its HPA were deleted afterwards (CLEAN UP).

---

## Exercise 4: Expose the Results Service Properly

### The brief
Results reachable from the **university network**, at a **stable address**, on **HTTP port 80**, on **its own path**, **without** giving enrolment the same exposure, **without a second load balancer**, plus the **cost** and the **failure mode**.

### Design – `manifests/lab-08/61-ingress-results.yaml`

| Choice | Rung | Why |
|---|---|---|
| `usms-results` stays a **ClusterIP** Service | rung 1 | nothing about the pods themselves is exposed |
| A new Ingress `usms-results-ingress` with **only `/results`** | rung 4 (Ingress) | its own path; enrolment is not in this object |
| `alb.ingress.kubernetes.io/group.name: usms-portal` | – | joins the **existing** portal Ingress's ALB – one load balancer, one bill |
| `conditions.usms-results`: **source-ip `10.10.0.0/16`** (example campus range) | – | only the university network matches the rule |
| `listen-ports` HTTP 80, `target-type: ip`, `healthcheck-path: /healthz` | – | a normal port; pod IPs as targets like Lab 05's target group |

**No second `type: LoadBalancer` Service**, because each one is a separate NLB and a separate bill, while extra paths on an Ingress group are just more rules on the same ALB.

### Evidence on this build
The Ingress was created and `describe` shows `/results → usms-results:80` resolved to the two results pod IPs, with all annotations (group, source-ip condition, port, target type). As in Step 16 there is **no ingress controller**, so it has no ADDRESS: the routing intent is stored and correct, but on real EKS it is the **AWS Load Balancer Controller** that would turn it into a listener rule on the shared ALB. The backend it points at answers with results JSON, and the Ingress declares only `/results`.

![Exercise 4 - Ingress created and described](LAB_08(image)/ex4.1.png)

![Exercise 4 - routing evidence](LAB_08(image)/ex4,2.png)

### Cost
- Sharing the portal's ALB: **no new load balancer**. An ALB is roughly **US$16–20 per month** plus LCU charges for traffic; adding a rule to it costs essentially nothing extra.
- A second `LoadBalancer` Service would be a separate NLB at a similar fixed monthly price, for one service – which is exactly what the brief wanted to avoid.
- The current gateway `LoadBalancer` Service (Step 15) is itself an extra NLB; in production I would move the gateway behind the same Ingress group too.

### Failure mode – if the cluster is unavailable
The ALB lives **outside** the cluster, so its DNS name stays the same and keeps accepting connections – but with no healthy pod targets it returns **HTTP 503** to the Examinations Office. If only the controller is down, the ALB keeps routing with its last known targets but stops updating them, so new or moved pods are not registered. Nothing breaks for enrolment, because this Ingress never routed it. To protect results, I would keep at least two results replicas (its HPA already has min 2) with a PDB, spread across AZs.

---

## Exercise 5: Artefacts for Lab 10, and the Argument

### Part 1 – `outputs/lab-08-scaling-evidence.json`
Built with python3 from **live** `kubectl` and `aws eks` calls, not typed: timestamp, source (Floci 2.4.0 / k3s v1.30.10), the HPA's full spec and status, the Deployment's replicas (2 / 2), the node group's scaling config (2 / 4 / 2), and – stated explicitly rather than left out – `nodegroup_resize: available false` with the `UnknownOperationException` text. `python3 -m json.tool` accepts it and it is git-ignored.

![Exercise 5 - scaling evidence](LAB_08(image)/ex5.1.png)

### Part 2 – `outputs/lab-08-lab06-readiness.txt`
Re-derived from the policy document (`get-policy` → `get-policy-version`), not copied from Lab 07:

| Item | Value |
|---|---|
| Policy | `arn:aws:iam::000000000000:policy/USMSStudentDataReadWrite` (v1) |
| Roles carrying it | usms-ec2-app-role, usms-ecs-task-role, usms-eks-node-role |
| Bucket ARN in Resource | `arn:aws:s3:::usms-student-data` (and `/*` for objects) |
| Bucket exists? | **No** – head-bucket 404, exit 255; created in Lab 10 |
| IRSA ServiceAccount | `usms/usms-enrolment-sa` |
| IRSA annotation | `eks.amazonaws.com/role-arn: arn:aws:iam::000000000000:role/usms-enrolment-s3-role` |

The annotation names a **new** role trusting the cluster's OIDC provider for `system:serviceaccount:usms:usms-enrolment-sa`, with USMSStudentDataReadWrite attached – **not** `usms-eks-node-role`, because the node role is inherited by every pod on the node, so pointing IRSA at it would give no isolation. (This build has no OIDC issuer, so the role is described, not created.)

![Exercise 5 - readiness](LAB_08(image)/ex5.2.png)

### Part 3 – "ECS or Kubernetes for USMS"
Appended to `notes/lab-08-notes.md` (under 400 words): **ECS on Fargate**, based on three observations – Fargate never leaves work Pending while the HPA and node group are two unconnected loops (and the node-group resize failed here); Labs 07–08 needed far more moving parts and the cluster had to be rebuilt from manifests twice; Lab 05's ALB was more hand work but done once. The strongest argument against it: Kubernetes let me watch and debug the autoscaler second by second, put every service behind one Ingress, and protect a drain with a PDB – none of which I could test on ECS.

![Exercise 5 - notes](LAB_08(image)/ex5.3.png)

---

## Summary

| Exercise | Result |
|---|---|
| 1 | Second HPA for usms-results (2–6, 60 %, 180 s window); both HPAs report percentages |
| 2 | Gateway at 2 replicas → ALLOWED DISRUPTIONS 1 with the PDB unchanged; kubectl diff caught a Service revert; eviction now allowed while serving |
| 3 | Two faults: no explicit request (defaulted to the 200m limit on this Kubernetes, not `<unknown>`) and min = max = 4; fixed with one field each → `0%/70%`, 4–8 |
| 4 | Results-only Ingress on the shared ALB group, restricted by source IP; stored, no controller on this build; cost and failure mode explained |
| 5 | Live scaling-evidence JSON, policy readiness with the IRSA annotation, and the ECS-vs-Kubernetes argument |