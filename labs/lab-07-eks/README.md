# AWS Practical Laboratory Report

**Name:** Namgyel Wangchuk
**Student No.:** 02230291
**Module:** DSO303
**Practical:** Lab 07 – Deploying a Microservices Application on Amazon EKS
**Date:** 13 October 2026

**Tools used:** Floci (local AWS emulator, Docker Compose, hybrid storage), AWS CLI v1, kubectl (client and server v1.34), Docker, python3, git, nano

**Floci support path: A.** `aws eks` works and starts a real k3s Kubernetes cluster in a Docker container, so both the AWS half and the Kubernetes half of this lab really ran.

---

## 1. Aim / Objective

The aim of this practical is to run the USMS application on Amazon EKS, the Kubernetes way, alongside the ECS version from Labs 04 to 06. That means creating an EKS cluster and a managed node group in Lab 02's VPC, each with its own IAM role, pointing kubectl at the cluster, deploying three microservices (usms-gateway, usms-enrolment and usms-results) from YAML manifests, proving they find each other by DNS name, doing a rolling update and a rollback, diagnosing three deliberate failures, using a ConfigMap and a Secret, and proving the setup survives a restart.

## 2. Introduction

Amazon Elastic Kubernetes Service (EKS) is AWS's managed Kubernetes. AWS runs the **control plane** (the API server, etcd, the scheduler and the controllers), and you run the **data plane** (the worker nodes and your pods). Kubernetes itself is open source and the same everywhere, so the manifests you write are portable to any Kubernetes cluster, while the AWS parts (IAM roles, VPC, node groups, load balancers) are not. EKS matters because Kubernetes has become the standard way to run many containerised services together: it handles scheduling, self-healing, service discovery, rolling updates and scaling with one consistent API.

### Key Features

- **Managed control plane:** AWS runs and patches the API server and etcd across several AZs
- **Managed node groups:** EC2 worker nodes with min / max / desired size, created from an AWS AMI
- **Two IAM roles:** a cluster role (trusts `eks.amazonaws.com`) and a node role (trusts `ec2.amazonaws.com`)
- **Deployments and ReplicaSets:** keep N copies of a pod running and roll out changes as new ReplicaSets
- **Services and CoreDNS:** a stable ClusterIP and DNS name in front of pods whose IPs keep changing
- **ConfigMaps and Secrets:** configuration and sensitive values kept outside the image
- **Probes:** readiness controls whether a pod gets traffic; liveness controls restarts
- **IRSA:** fine-grained AWS permissions per Kubernetes ServiceAccount (on real EKS)

## 3. Use Case

USMS wants to split its portal into small services that can be released and scaled separately: a gateway that receives every request, an enrolment service and a results service. The team also wants to compare running them on Kubernetes with the ECS setup from Labs 04 to 06.

| Need | How EKS / Kubernetes provides it |
|---|---|
| One entry point for the portal | `usms-gateway` (nginx) routes `/enrolment/` and `/results/` |
| Services must find each other without hard-coded IPs | Each Service has a DNS name, e.g. `usms-enrolment.usms.svc.cluster.local` |
| A crashed copy must come back by itself | The ReplicaSet replaces deleted or failed pods |
| Release new versions without downtime, and undo them | Rolling updates (new ReplicaSet) and `kubectl rollout undo` |
| Keep config and passwords out of the image | ConfigMaps and Secrets injected as environment variables |
| Work in Lab 02's network with least-privilege roles | Cluster across all 4 subnets, nodes in the private ones, two separate IAM roles |

## 4. System Architecture / Design

The AWS side lives in Lab 02's VPC; the Kubernetes side is three Deployments and three ClusterIP Services in namespace `usms`. On Floci, the whole Kubernetes cluster runs as one k3s container on my machine.

![alt text](LAB_07(image)/aws-architecture-diagram(5).png)

## 5. Implementation Procedure

I loaded the env files, checked Labs 02 and 04 were still intact, and probed Floci: `aws eks` and kubectl both worked, so I followed Path A. I wrote the two trust policies and two permissions policies, created `usms-eks-cluster-role` with `USMSEKSClusterPolicy`, the security group `usms-eks-cluster-sg` in usms-vpc, and `usms-eks-node-role` with `USMSEKSNodePolicy` plus Lab 01's `USMSStudentDataReadWrite`. I built the create-cluster request as a JSON template, assumed `usms-developer-role` and created `usms-eks-cluster` across all four subnets. The first attempt hit the CLI timeout because Floci was downloading the k3s image, so I pre-pulled it with `docker pull`. I then created the managed node group in the private subnets, pointed kubectl at the cluster with `update-kubeconfig`, created namespace `usms` and deployed usms-enrolment, usms-results and usms-gateway from manifests. I proved DNS-based service discovery and load spreading, added a Secret, did a rolling update and rollback, and broke pods on purpose three ways. Finally I tested a restart, found that Floci deletes the k3s container, rebuilt the cluster from my templates and manifests, wrote `configs/lab-07.env`, built the verify and cleanup scripts and committed, then did the five exercises.

## 6. Results and Evidence

### 6.1 CLI Output

**Screenshot 1**

Environment and earlier labs

![Step 1](LAB_07(image)/1.png)

*Identity 000000000000; verify-lab-02 32/1 and verify-lab-04 38/1 (known Floci failures); all four subnets present*

---

**Screenshot 2**

Support probe

![Step 2](LAB_07(image)/2.png)

*eks list-clusters OK and kubectl present: PATH A*

---

**Screenshot 3**

Trust policies

![Step 4](LAB_07(image)/4.png)

*cluster role trusts eks.amazonaws.com, node role trusts ec2.amazonaws.com*

---

**Screenshot 4**

Permissions policies

![Step 5](LAB_07(image)/5.png)

*Cluster policy 3 statements, node policy 5 statements, each ending with a region Deny*

---

**Screenshot 5**

Cluster role and security group

![Step 6.1](LAB_07(image)/6.1.png)

*usms-eks-cluster-role created, USMSEKSClusterPolicy attached, usms-eks-cluster-sg sg-179d99087f431aeeb with tcp/443 from 10.0.0.0/16*

---

**Screenshot 6**

Cluster role verify

![Step 6.2](LAB_07(image)/6.2.png)

*USMSEKSClusterPolicy, eks.amazonaws.com, security group in vpc-2a16e684 with port 443*

---

**Screenshot 7**

Node role and Lab 01's policy

![Step 7.1](LAB_07(image)/7.1.png)

*USMSStudentDataReadWrite now held by three roles: usms-ec2-app-role, usms-ecs-task-role, usms-eks-node-role*

---

**Screenshot 8**

Node role verify

![Step 7.2](LAB_07(image)/7.2.png)

*USMSEKSNodePolicy + USMSStudentDataReadWrite, trusts ec2.amazonaws.com*

---

**Screenshot 9**

Create-cluster request

![Step 8.1](LAB_07(image)/8.1.png)

*Request body with four real subnet IDs, the cluster SG, the role ARN and the _lb_ports_ tag; 0 unexpanded variables*

---

**Screenshot 10**

Creating the cluster

![Step 8.2](LAB_07(image)/8.2.png)

*Assumed usms-developer-role (session shown as floci-session), cluster created (ResourceInUseException on the final retry), back to root*

---

**Screenshot 11**

Cluster details

![Step 9.1](LAB_07(image)/9.1.png)

*ACTIVE, version 1.30, endpoint https://localhost:6500, 4 subnets, the cluster SG, _lb_ports_ 8081,8082; Vpc empty (Floci)*

---

**Screenshot 12**

Your turn: version and OIDC issuer

![Step 9.2](LAB_07(image)/9.2.png)

*1.30 and None - no OIDC issuer on this build*

---

**Screenshot 13**

Managed node group

![Step 10.1](LAB_07(image)/10.1.png)

*usms-eks-nodes ACTIVE straight away*

---

**Screenshot 14**

Node group details

![Step 10.2](LAB_07(image)/10.2.png)

*Private subnets only, usms-eks-node-role, min 2 / max 4 / desired 2, labels workload=usms tier=app*

---

**Screenshot 15**

kubectl connected

![Step 11.1](LAB_07(image)/11.1.png)

*update-kubeconfig worked; control plane at https://localhost:6500; one node Ready, v1.34.1+k3s1*

---

**Screenshot 16**

kubectl permissions and API

![Step 11.2](LAB_07(image)/11.2.png)

*1 node, "yes" to create deployments, namespaced resources listed*

---

**Screenshot 17**

Namespace

![Step 12](LAB_07(image)/12.png)

*Namespace usms Active with labels lab=07, project=usms, tier=app, set as the context default*

---

**Screenshot 18**

usms-enrolment applied

![Step 13.1](LAB_07(image)/13.1.png)

*ConfigMaps, Deployment and Service created*

---

**Screenshot 19**

usms-enrolment running

![Step 13.2](LAB_07(image)/13.2.png)

*2/2 ready, 2 pods (10.42.0.5, 10.42.0.6), ClusterIP 10.43.203.54, 2 endpoints*

---

**Screenshot 20**

usms-enrolment answers

![Step 13.3](LAB_07(image)/13.3.png)

*JSON with the real pod name, env laboratory, version 1.0.0*

---

**Screenshot 21**

usms-results

![Step 14](LAB_07(image)/14.png)

*Both Deployments 2/2; enrolment MAXUNAVAIL 0, results 25%*

---

**Screenshot 22**

usms-gateway

![Step 15](LAB_07(image)/15.png)

*5 pods Running; gateway log "Configuration complete; ready for start up"*

---

**Screenshot 23**

DNS from inside the cluster

![Step 16.1](LAB_07(image)/16.1.png)

*CoreDNS 10.43.0.10 resolves the Service names to ClusterIPs 10.43.203.54 and 10.43.241.178*

---

**Screenshot 24**

Routes through the gateway

![Step 16.2](LAB_07(image)/16.2.png)

*/, /enrolment/ and /results/ all answered by the right service*

---

**Screenshot 25**

Load spreading

![Step 16.3](LAB_07(image)/16.3.png)

*12 requests split 6 / 6 across the two enrolment pods*

---

**Screenshot 26**

Your turn: delete a pod

![Step 16 your turn](LAB_07(image)/16(yourturn).png)

*The ReplicaSet created a replacement within 1 s; all 12 requests still succeeded*

---

**Screenshot 27**

Your turn: new pod in the tally

![Step 16 your turn 2](LAB_07(image)/16(yourturn.2).png)

*The replacement pod 99m7g now serves traffic alongside gv46t*

---

**Screenshot 28**

Secret created outside git

![Step 17.1](LAB_07(image)/17.1.png)

*Secret manifest written to outputs/ and ignored by git*

---

**Screenshot 29**

base64 is not encryption

![Step 17.2](LAB_07(image)/17.2.png)

*The token decoded to plain text with one command*

---

**Screenshot 30**

Secret used by the Deployment

![Step 17.3](LAB_07(image)/17.3.png)

*Two secretKeyRef env entries; token and password readable inside the container*

---

**Screenshot 31**

ConfigMap change and restart

![Step 18.1](LAB_07(image)/18.1.png)

*Still 1.0.0 after the ConfigMap change; 1.1.0 only after rollout restart, with a new ReplicaSet hash*

---

**Screenshot 32**

Rollout history

![Step 18.2 history](LAB_07(image)/18.2(history).png)

*Three revisions and three ReplicaSets*

---

**Screenshot 33**

Rollback

![Step 18.2 undo](LAB_07(image)/18.2(undo).png)

*rollout undo back to ReplicaSet 7d8557c58d, but the response still says 1.1.0 - the ConfigMap is not rolled back*

---

**Screenshot 34**

Your turn: image change (watch)

![Step 18 your turn 1](LAB_07(image)/18(yourtur.1).png)

*Two old pods stayed Running while the new pod was stuck pulling nginx:1.27*

---

**Screenshot 35**

Your turn: image change and undo

![Step 18 your turn 2](LAB_07(image)/18(yourturn.2).png)

*rollout status timed out (slow pull), undo restored nginx:1.27-alpine; history shows revisions 2 and 3*

---

**Screenshot 36**

Failure 1: ImagePullBackOff

![Step 19.1](LAB_07(image)/19.1.png)

*New pod in ImagePullBackOff, the two old pods kept serving*

---

**Screenshot 37**

Failure 2: FailedScheduling

![Step 19.2](LAB_07(image)/19.2.png)

*usms-toobig Pending: 0/1 nodes are available: Insufficient cpu, Insufficient memory*

---

**Screenshot 38**

Failure 3: CrashLoopBackOff

![Step 19.3](LAB_07(image)/19.3.png)

*Container exits with code 1, logs show "fatal: no database configured", restart back-off*

---

**Screenshot 39**

Events after the failures

![Step 19.4](LAB_07(image)/19.4.png)

*Events show the full image pull error; back to 5 healthy pods*

---

**Screenshot 40**

ECS and EKS side by side

![Step 20](LAB_07(image)/20.png)

*ECS service (desired 2, usms-enrolment:2, 1 LB) next to the three Kubernetes Deployments and Services*

---

**Screenshot 41**

IRSA

![Step 21](LAB_07(image)/21.png)

*OIDC issuer None, no provider registered; ServiceAccount usms-enrolment-sa created without a role annotation*

---

**Screenshot 42**

Before and during the restart

![Step 22.1](LAB_07(image)/22.1.png)

*State recorded, Floci stopped and started, kubectl refused on localhost:6500*

---

**Screenshot 43**

After the restart

![Step 22.2](LAB_07(image)/22.2.png)

*Cluster and node group records re-derived from the API, but all Kubernetes objects missing*

---

**Screenshot 44**

Why: the Floci log

![Step 22.3](LAB_07(image)/22.3.png)

*"Stopped k3s container for cluster usms-eks-cluster" on stop; records reloaded on start; k3s never restarted*

---

**Screenshot 45**

Rebuilding the cluster

![Step 22.4](LAB_07(image)/22.4.png)

*Records deleted and recreated from the templates: ACTIVE, https://localhost:6500, 8081,8082*

---

**Screenshot 46**

Re-applying the application

![Step 22.5](LAB_07(image)/22.5.png)

*Whole app back from manifests/lab-07/ in about a minute: 2/2, 1/1, 2/2*

---

**Screenshot 47**

Kubernetes itself persists

![Step 22.6](LAB_07(image)/22.6.png)

*Restarting only the k3s container: KUBERNETES STATE PERSISTED, and SMOKE TEST PASSED*

---

**Screenshot 48**

configs/lab-07.env

![Step 23](LAB_07(image)/23.png)

*All values populated, lb_ports 8081,8082, endpoint port 6500, the right SG, 21 exports*

---

**Screenshot 49**

Verify, cleanup and commit

![Step 24](LAB_07(image)/24.png)

*verify-lab-07.sh PASS=30 FAIL=0; cleanup script syntax OK (not run); committed with nothing from outputs/ staged*

---

The exercise screenshots are in [`exercises.md`](exercises.md).

### 6.2 AWS Console Verification

Floci has no AWS Management Console, so console screenshots were not possible. The AWS side was checked with `aws eks describe-cluster`, `describe-nodegroup`, `aws iam` and `aws ec2` read-backs, and the Kubernetes side with kubectl (`get`, `describe`, `logs`, `top`). `verify-lab-07.sh` ran all 30 checks and passed every one. On real AWS the same checks would be done in the EKS console (Overview, Compute → Node groups, Resources → Workloads and Services) and the IAM and VPC consoles.

## 7. Analysis and Discussion

This was the most successful lab so far on Floci. Both halves ran for real: the EKS API created a cluster and kubectl talked to a genuine Kubernetes API server. All three microservices deployed, found each other by DNS name, spread load evenly (6/6), recovered from a deleted pod in about a second, rolled forward and back, and the verify script passed **30 out of 30**.

Where Floci differed from real AWS:

| What happened on Floci | What real AWS would do |
|---|---|
| The first `create-cluster` timed out and the CLI retried every ~60 s, because Floci was downloading the 243 MB `rancher/k3s:latest` image during the request | The control plane is created in AWS's accounts; the call returns at once with CREATING and takes 10–15 min |
| `describe-cluster` says 1.30, but kubectl shows **v1.34.1+k3s1** | The cluster runs the version you asked for |
| The node group was ACTIVE instantly, but there is **1 node** (the k3s container), not 2 t3.small instances | 2 real EC2 instances in the private subnets |
| Endpoint `https://localhost:6500` (lab expected 6443) | A public/private AWS endpoint URL |
| `resourcesVpcConfig.vpcId` returned empty | Worked out from the subnets (vpc-2a16e684) |
| Pods get `10.42.x.x` addresses, Services `10.43.x.x` | Pods get real addresses from 10.0.3.0/24 and 10.0.4.0/24 (VPC CNI) |
| OIDC issuer `None`, so no IRSA | An issuer URL; IRSA gives per-ServiceAccount credentials |
| IAM policies stored but not enforced; assumed session shown as `floci-session` | Missing permissions break cluster creation or node join |
| **Floci deletes the k3s container on `floci-down` and never restarts it** (log: `Stopped k3s container`) - records survive, Kubernetes objects are lost | The control plane and etcd are managed by AWS and persist |
| ECS showed runningCount 4 with desired 2 after a laptop shutdown | ECS would stop the extra tasks |

Some differences came from my newer Kubernetes and kubectl (1.34), not from Floci:
- `kubectl set env --from=secret` added two `secretKeyRef` env entries instead of one `envFrom.secretRef` (same result in the container).
- `v1 Endpoints is deprecated` warnings (EndpointSlice replaces it in 1.33+).
- With only 2 replicas, the "default 25%/25%" strategy rounds to maxUnavailable 0 / maxSurge 1, so usms-results rolled out the same way as usms-enrolment.

Things I fixed or changed along the way:
- The lab's namespace label `lab: "05a"` (an old lab number) was changed to `"07"`, and the session name to `lab07-eks-build`.
- `verify-lab-07.sh` got the same `.gitkeep` fix as earlier labs.
- The Secret manifest was written to `outputs/` instead of `manifests/`, so it can never be committed.
- My laptop shut down during Step 8; nothing was lost because the template was on disk and Floci keeps its records.

**Persistence (Step 22)** was only partly proven. The AWS records survived and were re-derived from `list-clusters` and `list-nodegroups`, but Floci removed the k3s container, so `describe-cluster` said ACTIVE while kubectl was refused. I proved the limitation is Floci's and not Kubernetes' by restarting only the k3s container with `docker restart`: every Deployment and Service came back. I recovered from the Floci restart by recreating the cluster from `templates/` and re-applying `manifests/lab-07/` in about a minute; the only manual step was `kubectl set env --from=secret`, because Step 17 added it with a command rather than a file.

**Observed:** the Kubernetes object model, DNS service discovery, load spreading, self-healing, rolling updates and rollback, all three failure modes, the PDB blocking an eviction, and Kubernetes state surviving a container restart. **Recorded only:** IAM policies, node group size and instance type, the security group. **Conceptual:** IRSA, KMS encryption of Secrets, access entries, control-plane logging, real pod VPC addresses.

## 8. Reflection

**What I learned.** The biggest lesson was the split between the control plane and the data plane: an ACTIVE cluster runs nothing until there are nodes, and the AWS side (roles, node groups) and the Kubernetes side (Deployments, Services) are two different worlds joined by kubectl. I also finally understood why Services exist: pod IPs kept changing all lab (10.42.0.5 became 10.42.0.23 and so on), but the gateway only ever used DNS names and never needed restarting. And I learned that a Secret is only base64 – I decoded one in a second – and that `rollout undo` only reverts the pod template, not the ConfigMap.

**Challenges.** Creating the cluster was the hardest part. The first attempt kept failing with a Java stack trace, and only by reading the Floci log did I see it was stuck downloading the k3s image and the CLI kept retrying; pre-pulling it fixed it. My laptop also shut down in the middle of Step 8, which taught me to check what state things are in before redoing anything. The restart test was the biggest surprise: the cluster said ACTIVE but nothing answered. Reading the Floci log showed it had removed the container, and I had to rebuild – which turned into a good demonstration of why everything should be in files.

**Real-world use.** For USMS I would still choose ECS on Fargate today, because it is one small team with a quiet service most of the year, and ECS gave me scaling and a load balancer with fewer moving parts. Kubernetes becomes worth it if USMS grows into many services or needs to run outside AWS. If I did use EKS, I would always keep manifests in Git, set resource requests, use PodDisruptionBudgets, and use IRSA instead of putting S3 permissions on the node role.

**What I want to explore next.** Lab 08's HorizontalPodAutoscaler (metrics-server is already running here), exposing the gateway with a LoadBalancer and an Ingress, and trying IRSA on a real EKS cluster where the OIDC issuer exists. I'd also like to try GitOps tools that re-apply manifests automatically, since Step 22 showed how valuable that is.

## 9. Conclusion

The objectives of this practical were achieved on Floci's Path A. An EKS cluster and managed node group were created in Lab 02's VPC with separate cluster and node roles, kubectl was connected to a real Kubernetes API, and three microservices were deployed declaratively and proven to discover each other by DNS, spread load, heal themselves, roll forward and back, and handle three kinds of failure. A ConfigMap and a Secret were used, and the Secret was shown to be readable, not encrypted. The verify script passed all 30 checks. Persistence was only partly met because Floci deletes the Kubernetes container on restart, but the application was rebuilt from Git in about a minute, and a separate test showed Kubernetes itself keeps its state.

The key skills I practised were writing and applying manifests, reading Kubernetes status with get / describe / logs / events, diagnosing failures from Events rather than guessing, and comparing EKS with ECS while both were running. This leaves the cluster, the `usms` namespace, the CPU requests and the `_lb_ports_` tag ready for Lab 08.

## 10. Appendix

### Additional Files

- `policies/trust-eks-cluster.json`, `policies/trust-eks-node.json`
- `policies/usms-eks-cluster-policy.json`, `policies/usms-eks-node-policy.json`
- `templates/lab-07-create-cluster.json`, `templates/lab-07-create-nodegroup.json`
- `manifests/lab-07/00-namespace.yaml`, `10-configmap-app.yaml`, `20-enrolment.yaml`, `25-enrolment-pdb.yaml`, `30-results.yaml`, `40-gateway.yaml`, `60-serviceaccount.yaml`, `70-timetable.yaml`
- `configs/lab-07.env`
- `scripts/utilities/eks-support-probe.sh`, `scripts/utilities/verify-lab-07.sh`
- `scripts/cleanup/lab-07-cleanup.sh` (written, not run)
- `labs/lab-07-eks/exercises.md`
- `notes/lab-07-notes.md`

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