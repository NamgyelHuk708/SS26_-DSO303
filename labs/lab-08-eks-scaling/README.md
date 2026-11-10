# AWS Practical Laboratory Report

**Name:** Namgyel Wangchuk
**Student No.:** 02230291
**Module:** DSO303
**Practical:** Lab 08 – EKS Scaling and Service Exposure
**Date:** 9 November 2026

**Tools used:** Floci (local AWS emulator, Docker Compose, hybrid storage – **upgraded to 2.4.0**, see Section 7), AWS CLI v1, kubectl, k3s v1.30.10 (the EKS cluster from Lab 07), Docker, python3, git

**Support path: A.** The `eks` API answers and the Kubernetes cluster is real. One AWS-side call (`update-nodegroup-config`) is a recorded Known Issue and was replaced by the course's documented alternative.

---

## 1. Aim / Objective

The aim of this practical is to make Lab 07's three microservices scale and become reachable. On the scaling side: scale a Deployment by hand, by manifest and automatically with an `autoscaling/v2` HorizontalPodAutoscaler, compare it with Lab 06's Application Auto Scaling, try to change the node group from the AWS side, and use requests, QoS classes, a nodeSelector and PodDisruptionBudgets. On the exposure side: climb the ladder ClusterIP → port-forward → NodePort → LoadBalancer → Ingress, and compare the Ingress with Lab 05's ALB. Finally, prove the configuration survives a restart and save it to `configs/lab-08.env`.

## 2. Introduction

Kubernetes separates **how many** copies of a service run from **where** they run and **how** they are reached. Scaling is always one integer written by someone: `spec.replicas` written by me (`kubectl scale`), by Git (the manifest) or by the HPA controller, and – on a different API – the node group's `desiredSize`, written by me or by a Cluster Autoscaler / Karpenter. Exposure is a ladder of Service types, each keeping the one below it, topped by an Ingress that routes many paths through one load balancer. This matters because it is how a real EKS workload absorbs a registration-week surge without paying for peak capacity all year, and how it is exposed safely.

### Key Features

- **HorizontalPodAutoscaler (autoscaling/v2):** scales replicas from CPU as a percentage of the **request**, with `behavior` rate limits and a scale-down stabilisation window
- **Requests, limits and QoS classes:** requests are what the scheduler reserves and the HPA divides by; limits are enforced at runtime
- **nodeSelector:** a hard scheduling rule using node labels
- **PodDisruptionBudget:** limits voluntary evictions (drain, autoscalers), not deletes or crashes
- **Service types:** ClusterIP ⊂ NodePort ⊂ LoadBalancer
- **Ingress:** HTTP path routing for many Services behind one address; on EKS the AWS Load Balancer Controller turns it into an ALB
- **Managed node group scaling:** min / max / desired on the AWS side – a separate control loop from the HPA

## 3. Use Case

USMS is quiet most of the year and very busy during enrolment weeks. The Examinations Office also needs the results service reachable from campus.

| Need | How it is met |
|---|---|
| Add enrolment capacity automatically when CPU rises, and release it slowly afterwards | `usms-enrolment-hpa`: min 2, max 8, 50 % of the 50m request, instant scale-up, 300 s scale-down window |
| Make sure the HPA's numbers mean something | an explicit CPU request on every container (the HPA's denominator) |
| Keep enrolment pods only on the USMS node group | `nodeSelector: workload=usms` |
| Never lose all gateway or enrolment pods during maintenance | PodDisruptionBudgets on both |
| Debug a service from a laptop | `kubectl port-forward` |
| Reach the portal from outside on one address | `usms-gateway` as type LoadBalancer |
| Expose several services by path through one load balancer | `usms-portal-ingress` (and `usms-results-ingress` for campus) |

## 4. System Architecture / Design

![alt text](LAB_08(image)/architecture.png)

## 5. Implementation Procedure

Before starting, I found that `floci-up.sh` had pulled a new `floci/floci:latest` image (**2.0.1 → 2.4.0**), that kubectl was pointing at my DSO202 kind cluster, and that the EKS cluster had come back as an **empty** k3s cluster whose `update-kubeconfig` token was rejected. I switched kubectl to the k3s admin kubeconfig (context `usms-eks-k3s`, file kept in `outputs/`), re-applied `manifests/lab-07/` and the Secret, and confirmed `verify-lab-07.sh` PASS=30 FAIL=0. I prepared the Lab 08 manifests and scripts as one set of files (listed in `files-from-zip`) and then applied and checked them step by step. I recorded a baseline, scaled usms-enrolment by hand and by file, read QoS classes and the scheduler's allocation, created the HPA and drove it with a load generator, attempted the node-group resize, proved a nodeSelector and two PodDisruptionBudgets, and climbed the exposure ladder from port-forward to Ingress. I then filled in the ECS/EKS comparison, proved persistence by restarting the k3s container, wrote `configs/lab-08.env`, verified, committed, and completed the five exercises.

## 6. Results and Evidence

### 6.1 CLI Output

**Screenshot 1**

Recovering the cluster after the Floci upgrade

![Step 0](LAB_08(image)/0.3.png)

*Lab 07 application re-applied from manifests on the new k3s cluster; smoke test passed through gateway, enrolment, results and timetable*

*Image Source: N/A*

---

**Screenshot 2**

Starting checks

![Step 1](LAB_08(image)/1.png)

*Context usms-eks-k3s, CPU request 50m, _lb_ports_ 8081,8082, verify-lab-07 PASS=30 FAIL=0*

*Image Source: N/A*

---

**Screenshot 3**

Baseline

![Step 2](LAB_08(image)/2.png)

*4 Deployments at their Lab 07 counts, all Services ClusterIP, 1 node (12 CPU capacity)*

*Image Source: N/A*

---

**Screenshot 4**

Scaling by hand to 5

![Step 4.1](LAB_08(image)/4.1.png)

*5/5 on the same ReplicaSet 6cc746dc8b – kubectl scale writes one field, no new ReplicaSet*

*Image Source: N/A*

---

**Screenshot 5**

Watcher during the scale

![Step 4.1 watcher](LAB_08(image)/4.1(terminal_2).png)

*New pods Running 0/1 at 2 s, 1/1 at 6 s – endpoints only grow when the readiness probe passes; Terminating on scale-in*

*Image Source: N/A*

---

**Screenshot 6**

Scaling back down

![Step 4.3](LAB_08(image)/4.3.png)

*Back to 2 endpoints; traffic had been spread over all five pods (10/9/7/7/7 of 40)*

*Image Source: N/A*

---

**Screenshot 7**

Configuration drift

![Step 5.1](LAB_08(image)/5.1.png)

*Cluster 6, file 2 – kubectl apply silently put it back to 2*

*Image Source: N/A*

---

**Screenshot 8**

kubectl diff and restore

![Step 5.2](LAB_08(image)/5.2.png)

*diff showed replicas 2 -> 3 before applying; restored to 2/2, no .bak files, git diff empty*

*Image Source: N/A*

---

**Screenshot 9**

QoS classes

![Step 6.1](LAB_08(image)/6.1.png)

*Every pod Burstable, 50m request / 200m limit*

*Image Source: N/A*

---

**Screenshot 10**

The scheduler's arithmetic

![Step 6.2](LAB_08(image)/6.2.png)

*CPU requests 500m = 25 % of allocatable (about 2 CPUs, not the 12 of capacity); 50 % target = 25m per pod*

*Image Source: N/A*

---

**Screenshot 11**

Your turn: Guaranteed and back

![Step 6.3](LAB_08(image)/6.3.png)

*Burstable -> Guaranteed (requests = limits) -> Burstable; the pod was replaced each time, the original ReplicaSet reused at the end*

*Image Source: N/A*

---

**Screenshot 12**

Metrics pipeline

![Step 7](LAB_08(image)/7.png)

*metrics API AVAILABLE (k3s ships metrics-server); pods idle at 1m = 2 % of the request*

*Image Source: N/A*

---

**Screenshot 13**

The HPA

![Step 8](LAB_08(image)/8.png)

*usms-enrolment-hpa cpu 2%/50%, min 2 max 8; ScalingActive True "percentage of request"*

*Image Source: N/A*

---

**Screenshot 14**

Load generator

![Step 9.1](LAB_08(image)/9.1.png)

*usms-loadgen: 3 busybox pods looping wget through the gateway*

*Image Source: N/A*

---

**Screenshot 15**

The HPA scaling out

![Step 9.2](LAB_08(image)/9.2.png)

*CPU 38 % -> 63 % and replicas 2 -> 3 (ceil(2 x 63/50) = 3); new pod Ready within 10 s*

*Image Source: N/A*

---

**Screenshot 16**

Holding, then scaling in

![Step 9.3](LAB_08(image)/9.3.png)

*Load removed: CPU 2 % at once, replicas held at 3 for the 300 s window, then back to 2*

*Image Source: N/A*

---

**Screenshot 17**

The HPA's own explanation

![Step 9.4](LAB_08(image)/9.4.png)

*SuccessfulRescale events with the reason strings ("above target", "All metrics below target")*

*Image Source: N/A*

---

**Screenshot 18**

Node group before

![Step 10.1](LAB_08(image)/10.1.png)

*usms-eks-nodes ACTIVE, min 2 / max 4 / desired 2, t3.small, private subnets, labels workload=usms tier=app*

*Image Source: N/A*

---

**Screenshot 19**

The resize fails

![Step 10.2](LAB_08(image)/10.2.png)

*update-nodegroup-config: UnknownOperationException (Known Issue); scaling config unchanged; still 1 node*

*Image Source: N/A*

---

**Screenshot 20**

The documented alternative

![Step 10.3](LAB_08(image)/10.3.png)

*Floci 2.4.0 version and the HPA drill evidence (Known Issues page, Lab 08)*

*Image Source: N/A*

---

**Screenshot 21**

Node labels and the selector

![Step 11.1](LAB_08(image)/11.1.png)

*The node group's labels reached the node; nodeSelector workload=usms rolled out*

*Image Source: N/A*

---

**Screenshot 22**

Selector enforcement

![Step 11.2](LAB_08(image)/11.2.png)

*workload=nonexistent: new pod Pending with FailedScheduling "didn't match Pod's node affinity/selector", the old pods kept serving*

*Image Source: N/A*

---

**Screenshot 23**

Put back and recorded in Git

![Step 11.3](LAB_08(image)/11.3.png)

*nodeSelector restored, added to manifests/lab-07/20-enrolment.yaml, kubectl diff empty*

*Image Source: N/A*

---

**Screenshot 24**

PodDisruptionBudgets

![Step 12.1](LAB_08(image)/12.1.png)

*gateway minAvailable 1 -> ALLOWED 0; enrolment maxUnavailable 1 -> ALLOWED 1*

*Image Source: N/A*

---

**Screenshot 25**

Eviction vs delete

![Step 12.2](LAB_08(image)/12.2.png)

*Eviction API: TooManyRequests "would violate the pod's disruption budget"; plain delete went straight through*

*Image Source: N/A*

---

**Screenshot 26**

Drain (dry run)

![Step 12.3](LAB_08(image)/12.3.png)

*What a drain would evict; node still Ready*

*Image Source: N/A*

---

**Screenshot 27**

ClusterIP from the laptop

![Step 13.1](LAB_08(image)/13.1.png)

*10.100.75.58 is not routable from my machine*

*Image Source: N/A*

---

**Screenshot 28**

port-forward

![Step 13.2 terminal 1](LAB_08(image)/13.2(t1).png)

*All three routes through localhost:18080; 6 of 6 requests to one pod – a tunnel to one pod, no load balancing*

*Image Source: N/A*

---

**Screenshot 29**

port-forward tunnel

![Step 13.2 terminal 2](LAB_08(image)/13.2(t2).png)

*The tunnel only exists while this command runs*

*Image Source: N/A*

---

**Screenshot 30**

NodePort inside the cluster

![Step 14.1](LAB_08(image)/14.1.png)

*usms-results-np 80:30080; through the node IP 172.17.0.3 both results pods answered (3/3)*

*Image Source: N/A*

---

**Screenshot 31**

NodePort from the laptop

![Step 14.2](LAB_08(image)/14.2.png)

*Host port 30080 belongs to my DSO202 kind cluster (nginx 404); the Floci k3s container publishes only 6443 -> 6500*

*Image Source: N/A*

---

**Screenshot 32**

NodePort fallback

![Step 14.3](LAB_08(image)/14.3.png)

*port-forward on 30081 returns the results JSON*

*Image Source: N/A*

---

**Screenshot 33**

LoadBalancer

![Step 15.1](LAB_08(image)/15.1.png)

*usms-gateway LoadBalancer: <pending> -> EXTERNAL-IP 172.17.0.3*

*Image Source: N/A*

---

**Screenshot 34**

The ladder on one line

![Step 15.2](LAB_08(image)/15.2.png)

*Fulfilled by k3s ServiceLB (svclb pod); 8081/8082 not published; type=LoadBalancer clusterIP=10.100.75.58 nodePort=30192 external=172.17.0.3*

*Image Source: N/A*

---

**Screenshot 35**

Ingress

![Step 16.1](LAB_08(image)/16.1.png)

*No IngressClass and no controller; usms-portal-ingress stored with CLASS <none> and no ADDRESS*

*Image Source: N/A*

---

**Screenshot 36**

What the Ingress resolved

![Step 16.2](LAB_08(image)/16.2.png)

*Each path already resolved to pod endpoints; nothing implements it on this build*

*Image Source: N/A*

---

**Screenshot 37**

ECS and EKS side by side

![Step 17](LAB_08(image)/17.png)

*ECS: desired 2 running 2, loadBalancers now retained; application-autoscaling answers (null). EKS: Deployments, HPA, Services, Ingress, PDBs*

*Image Source: N/A*

---

**Screenshot 38**

Before the restart

![Step 18.1](LAB_08(image)/18.1.png)

*HPA, PDBs, Services, Ingress recorded; k3s container restarted*

*Image Source: N/A*

---

**Screenshot 39**

After the restart

![Step 18.2](LAB_08(image)/18.2.png)

*PERSISTENCE PROVEN – identical, including the pinned NodePort 30080 and the allocated 30192*

*Image Source: N/A*

---

**Screenshot 40**

Node group re-read

![Step 18 check](LAB_08(image)/18(check).png)

*The "Path B" line was only unset variables; re-read, the node group is still 2/4/2*

*Image Source: N/A*

---

**Screenshot 41**

configs/lab-08.env

![Step 19](LAB_08(image)/19.png)

*19 exports; hpa 2..8 at 50 %, 300 s; NodePort 30080; gateway LoadBalancer; node group 2/4/2; Ingress class empty (expected)*

*Image Source: N/A*

---

**Screenshot 42**

Verify and commit

![Step 20](LAB_08(image)/20.png)

*verify-lab-08.sh PASS=33 FAIL=1 (only "node group maxSize raised to 6" – the Known Issue); committed with nothing from outputs/*

*Image Source: N/A*

---

The exercise screenshots are in [`EXERCISE.md`](EXERCISE.md).

### 6.2 AWS Console Verification

Floci has no AWS Management Console. The AWS side was checked with `aws eks describe-cluster`, `describe-nodegroup` and `aws ecs describe-services`; the Kubernetes side with `kubectl get / describe / top / diff` and the HPA's own Conditions and Events; `verify-lab-08.sh` checked 34 items. On real AWS the same checks would be made in the EKS console (Compute → Node groups, Resources → Workloads, Autoscaling, Services and Ingresses) and the EC2 console's Load Balancers page.

## 7. Analysis and Discussion

**What worked natively.** Manual and declarative scaling, drift and `kubectl diff`, QoS classes, the metrics pipeline, the HPA (2 → 3 under load, held 300 s, back to 2), the nodeSelector, both PodDisruptionBudgets and the eviction API, port-forward, NodePort (in-cluster), a LoadBalancer Service with a real external address from k3s ServiceLB, and persistence of every object across a k3s restart. Verify passed 33 of 34 checks.

**What I observed that differs from the lab text:**

| Observation | Explanation |
|---|---|
| HPA went 2 → **3**, not 4 | desiredReplicas = ceil(2 × 63/50) = 3. The scale-up policies (double, or +2 per 15 s) are **limits on speed**, not a required step size |
| Allocatable CPU ≈ 2 cores although capacity shows 12 | requests 500m = 25 %; Floci 2.4.0 gives the node a t3.small-like allocatable size |
| Exercise 3's "missing request" did not give `<unknown>` | the API server defaulted requests to the limits (200m), so the HPA worked against the wrong denominator instead (see EXERCISE.md) |
| `--dry-run=client` drain listed the gateway pod as evictable | client dry runs do not ask the PDB; the real eviction call was refused |

**Floci limitations and environment issues (honestly recorded):**

| Issue | Real AWS behaviour |
|---|---|
| **Floci upgraded itself 2.0.1 → 2.4.0** (`floci/floci:latest`) between labs; the course page warns against mid-semester upgrades | – (reported to the instructor) |
| The EKS cluster came back as an **empty** k3s cluster; rebuilt from `manifests/lab-07/` | the managed control plane and etcd persist |
| `update-kubeconfig`'s IAM token rejected; used the k3s admin kubeconfig (git-ignored) | IAM authenticator / access entries work |
| `update-nodegroup-config` → **UnknownOperationException** (Known Issue, also on 2.4.0); the HPA drill was used as the documented alternative | the node group's ASG launches a third node |
| Only **one node**; the node group's 2–4 nodes are a record | real EC2 nodes in two AZs |
| `_lb_ports_` host ports 8081/8082 not published; NodePort not published to the host | an NLB/ALB in the public subnets; NodePorts reachable inside the VPC |
| No ingress controller: Ingress stored but not implemented | the AWS Load Balancer Controller creates an ALB |
| No Cluster Autoscaler / Karpenter (need IRSA) | install with IRSA |

Floci 2.4.0 also behaved **more** like EKS than 2.0.1: the cluster really runs v1.30, nodes have EC2-style names, Services use 10.100.0.0/16, node group labels reach the node, ECS now keeps `loadBalancers` on readback and Application Auto Scaling answers. **My own environment** caused two traps: my DSO202 kind cluster had become the current kubectl context, and it also owns host port 30080, so `curl localhost:30080` reached the wrong cluster.

**Observed / recorded / conceptual.** *Observed:* everything in "what worked natively". *Recorded but not enacted:* the node group sizes, the AWS load-balancer annotations, the Ingress. *Conceptual:* the AWS Load Balancer Controller, Cluster Autoscaler, Karpenter, custom metrics, cost.

## 8. Reflection

**What I learned.** The clearest lesson was that scaling is one integer and the only question is who writes it – me, Git or the HPA – and that the node count is a *different* integer on a *different* API that nothing connects unless an autoscaler is installed. I also learned that the HPA's percentage is of the **request**, so the request is part of the scaling design, not just a scheduling detail; Exercise 3 showed how a missing request quietly turns into the limit. On exposure, the one-line ladder (`type=LoadBalancer clusterIP=… nodePort=30192 external=172.17.0.3`) made "each rung keeps the one below it" concrete.

**Challenges.** The hardest part came before Step 1: Floci had upgraded itself, kubectl was talking to a different course's cluster, the EKS cluster was empty and my login was rejected. Working out each of those from `docker ps`, `kubectl config` and the k3s container taught me more about how the pieces connect than the lab steps did. `kubectl diff` saved me in Exercise 2, when applying the Lab 07 gateway file would have silently turned my LoadBalancer back into a ClusterIP.

**Real-world use.** For USMS I would still pick ECS on Fargate, because Fargate never leaves work Pending for lack of nodes, but if we used EKS I would always set requests, let the HPA own `replicas`, run at least two replicas behind every PDB, use one Ingress per load balancer group, and always run `kubectl diff` and check `kubectl config current-context` first.

**What I want to explore next.** A multi-node cluster (k3d with agents) to see Pending pods and node-level PDB behaviour, the AWS Load Balancer Controller on real EKS, and re-running Lab 06 now that Application Auto Scaling answers on Floci 2.4.0.

## 9. Conclusion

The scaling objectives were met: usms-enrolment was scaled by hand, by manifest and automatically by an `autoscaling/v2` HPA that went 2 → 3 under load and back after its 300-second window, with requests, QoS, a nodeSelector and two PDBs proven along the way. The node-group resize failed with a recorded Known Issue and the course's alternative was used. The exposure ladder was climbed to a working LoadBalancer, with the Ingress stored but not implemented because no controller runs on this build. Persistence was proven across a k3s restart, `configs/lab-08.env` holds 19 values, and verify passed 33 of 34 checks.

## 10. Appendix

### Additional Files

- `manifests/lab-08/10-hpa-enrolment.yaml`, `11-hpa-results.yaml`, `20-loadgen.yaml`, `30-pdb-gateway.yaml`, `40-service-nodeport.yaml`, `50-service-loadbalancer.yaml`, `60-ingress.yaml`, `61-ingress-results.yaml`
- `manifests/lab-07/20-enrolment.yaml` (nodeSelector), `25-enrolment-pdb.yaml` (maxUnavailable 1), `40-gateway.yaml` (2 replicas, Service moved to Lab 08's file)
- `configs/lab-08.env`
- `scripts/utilities/hpa-watch.sh`, `verify-lab-08.sh`, `lab-08-add-nodeselector.py`
- `scripts/cleanup/lab-08-cleanup.sh` (written, not run)
- `labs/lab-08-eks-scaling/EXERCISE.md`, `exercise-files/ex3-usms-reports-broken.yaml`
- `notes/lab-08-notes.md`

### Submission Checklist

- [x] Student information completed
- [x] Objectives stated
- [x] Introduction provided
- [x] Real-world use case described
- [x] Tools listed
- [x] System design included
- [x] Implementation documented
- [x] CLI outputs included
- [x] Console verification addressed (Floci has no console, see 6.2)
- [x] Analysis completed
- [x] Reflection completed
- [x] Conclusion written