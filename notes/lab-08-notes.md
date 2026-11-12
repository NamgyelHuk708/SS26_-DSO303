# Lab 08 notes

## Environment changes before starting
- Floci was upgraded from 2.0.1 to 2.4.0 by floci-up.sh (floci/floci:latest). The new k3s
  cluster really runs v1.30.10, nodes are named like EC2 instances, and Services use 10.100.x.x.
- The cluster came back empty, so I re-applied manifests/lab-07/ and the Secret.
- update-kubeconfig's token was rejected, so I use the k3s admin kubeconfig as context usms-eks-k3s.
- My DSO202 kind cluster had become the current context - always check kubectl config current-context.

## Step 3 - ten times the traffic for usms-enrolment
1. Dimension 1 first (more pods): raise maxReplicas / let the HPA add replicas.
   Check: the new pods become Ready, not Pending, and CPU per pod drops below the target.
2. Dimension 3 next (more nodes): if pods go Pending with "Insufficient cpu", raise the node
   group's desiredSize (or let Cluster Autoscaler / Karpenter do it). Check: new nodes Ready
   and the Pending pods schedule.
3. Dimension 2 only if one pod is too small for a single request: raise requests/limits.
   Check: it restarts every pod and changes the HPA's denominator, so re-read the percentages.
4. Dimension 4 last: bigger instance types cannot be changed in place - create a new node group,
   cordon and drain the old one, then delete it. Plan it before Monday, not during the rush.

## Step 10 - node group resize (Known Issue, Lab 08)
- Command: aws eks update-nodegroup-config --scaling-config minSize=2,maxSize=6,desiredSize=3
- Error: UnknownOperationException - Unknown operation: POST /clusters/usms-eks-cluster/node-groups/usms-eks-nodes/update-config
- Floci version: server 2.4.0 (the Known Issues page records the same failure on 2.0.1)
- Readback after: scalingConfig still minSize 2 / maxSize 4 / desiredSize 2; Kubernetes still shows 1 node
- Alternative (Known Issues page): the Lab 8 HPA drill from Steps 8-9. Observed: under load CPU reached 63%
  and the HPA scaled usms-enrolment 2 -> 3 (ceil(2 x 63/50) = 3); after the load was removed it held 3 for
  the 300 s window, then scaled back to 2 ("All metrics below target").
- Proves: load changes pod replicas automatically (dimension 1).
  Does not prove: adding nodes (dimension 3) or the managed node-group API. A node resize would need a
  multi-node cluster and still would not emulate update-nodegroup-config.
- Label: node-group resize = not yet demonstrated; pod autoscaling = original feature demonstrated.

## Step 16 - Ingress with no controller (Conceptual)
No IngressClass and no controller pod on this build, so usms-portal-ingress is stored (CLASS <none>, no
ADDRESS) but nothing implements it. describe shows each path already resolved to pod endpoints.
On real EKS the AWS Load Balancer Controller would run, on my behalf, the same calls I typed in Lab 05:
1. aws elbv2 create-load-balancer   - scheme internet-facing, in the two PUBLIC subnets
                                      (alb.ingress.kubernetes.io/scheme)
2. aws elbv2 create-target-group    - one per backend Service (enrolment, results, gateway),
                                      --target-type ip, health check /healthz
                                      (target-type and healthcheck-path annotations)
3. aws elbv2 create-listener        - HTTP:80 (listen-ports annotation), default -> the gateway's group
4. aws elbv2 create-rule            - one per path: /enrolment and /results
...then register-targets/deregister-targets with the pod IPs, continuously, as Endpoints change.
Difference from Lab 05: the ALB used numeric rule priority (priority 10); an Ingress uses the
longest matching prefix, so /enrolment/x goes to enrolment even though / also matches.
And ten paths on one Ingress is still ONE load balancer.

## Step 17 - Practical 2 and Practical 4, compared with both running

### Scaling
| Question | ECS + Application Auto Scaling | Kubernetes + HPA |
| --- | --- | --- |
| What integer is written? | the service's desiredCount (2 now) | the Deployment's spec.replicas (2 now, was 3 under load) |
| Who writes it? | Application Auto Scaling, through scaling policies | the HPA controller (usms-enrolment-hpa) |
| Where does that thing run? | an AWS service outside anything I own | inside the cluster's controller manager (on EKS, run by AWS) |
| Where does the metric come from? | CloudWatch (AWS/ECS CPUUtilization, ALB RequestCountPerTarget) | metrics.k8s.io from metrics-server, every 15 s |
| What does "50% CPU" mean - 50% of what? | 50% of the task's reserved CPU | 50% of the container's request (50m), i.e. 25m per pod |
| How is scale-in slowed down? | ScaleInCooldown 300 | scaleDown stabilizationWindowSeconds 300 + 1 pod per 60 s (observed: held 3 for ~5 min) |
| No capacity for the new instance/pod? | Fargate always finds capacity | the pod stays Pending until a node is added (no Cluster Autoscaler here) |
| What creates the alarms? | Target tracking creates two CloudWatch alarms automatically | no alarms; the controller polls the metrics API |

### Exposure
| Question | ECS + ALB (Lab 05) | Kubernetes + Ingress (Step 16) |
| --- | --- | --- |
| AWS objects created by hand | 6: ALB SG, ALB, target group, listener, rule, SG cutover | 0: one Ingress object (the controller would create them) |
| Target type, and why | ip - Fargate tasks have their own VPC IPs | ip (annotation) - pods have their own VPC IPs via the VPC CNI |
| How targets register/deregister | the ECS service registers task IPs | the controller watches Endpoints and registers pod IPs |
| Competing rules disambiguated by | numeric priority (rule 10) | longest matching prefix (/enrolment beats /) |
| Moving to another cloud | rebuild everything (ALB, TG, listener are AWS-only) | keep the Ingress; only the alb.* annotations / ingress class change |
| Cost of exposing ten services | one ALB with ten rules, or ten ALBs if done per service | one Ingress = one ALB; ten LoadBalancer Services = ten NLBs |

### 1. If the AWS control plane has a bad afternoon
Application Auto Scaling and CloudWatch are AWS services, so if they are degraded ECS stops scaling and I can
only read what AWS shows me. The HPA runs inside the cluster and reads metrics-server, so it keeps working as long as
the cluster's own control plane is up, and I can debug it with kubectl describe hpa, its Conditions and Events,
kubectl top - all of which I used in this lab. But on EKS the cluster control plane is also run by AWS, so a bad
day for EKS itself would stop both; the HPA is more independent, not fully independent.

### 2. For USMS
I would still choose ECS on Fargate: one small team, quiet for eight months, and Fargate never leaves a task
Pending for lack of nodes. The strongest argument against my choice is what this lab showed - Kubernetes gave
me in-cluster scaling I could watch and debug second by second (63% -> 3 pods, then the 300 s hold), and one
Ingress could expose every service behind one load balancer, which ECS would need more hand-built ALB rules for.

## ECS or Kubernetes for USMS (Exercise 5, Part 3)

**Recommendation: ECS on Fargate.** USMS is one small team in one region, quiet for eight months and very
busy for two. Three things I observed decide it for me:

1. **Capacity.** On ECS (Lab 06) desiredCount is the only number; Fargate always finds room for a new task.
   On Kubernetes there are two control loops: the HPA raised replicas (2 -> 3 at 63% CPU in Lab 08), but nodes
   are a separate integer, and update-nodegroup-config failed (UnknownOperationException). Without a Cluster
   Autoscaler or Karpenter, a real surge would leave pods Pending.
2. **Operational load.** Lab 07 and Lab 08 needed two IAM roles, a node group, Ingress controllers, PDBs and
   careful manifests; my cluster was wiped twice by an emulator restart and rebuilt from manifests/lab-07/.
   Lab 04's ECS service survived every restart as an AWS object.
3. **Exposure.** Lab 05 needed six hand-made ALB objects, which is real work, but they were done once.

**The strongest argument against my choice:** Kubernetes gave me things ECS could not. I could watch and
debug the autoscaler second by second (kubectl describe hpa, the 300 s hold, "All metrics below target"),
one Ingress could put every service behind one ALB by path, and the manifests are portable to any cluster.
A PDB stopped a drain from taking the last pod - ECS has no equivalent I could test. If USMS grew to many
services, or needed to leave AWS, those advantages would outweigh the extra moving parts.


