## Lab 07 support path
Probed on 2026-10-12T18:11:04Z
PATH A  - use aws eks throughout

## Step 20 - ECS and Kubernetes, compared with both running

| Question | ECS answer | Kubernetes answer |
| --- | --- | --- |
| What holds the container spec? | Task definition (usms-enrolment:2, immutable revisions) | Pod template inside the Deployment (manifests/lab-07/20-enrolment.yaml) |
| What keeps N copies alive? | The ECS service (desiredCount 2) | The ReplicaSet owned by the Deployment (replicas 2) |
| What gives it a stable name? | The ALB DNS name and target group (Lab 05) | The Service: ClusterIP 10.43.203.54 + DNS name usms-enrolment.usms.svc.cluster.local |
| How does another service find it? | Calls the ALB, which forwards to registered task IPs | CoreDNS resolves the Service name; kube-proxy spreads to ready pods |
| What does a rolling update create? | A new deployment of a new task-definition revision | A new ReplicaSet (new pod-template hash) |
| Where does rollback state live? | Old task definition revisions | Old ReplicaSets, kept up to revisionHistoryLimit (5) |
| Which IAM role does the app code use? | Task role usms-ecs-task-role | Node role usms-eks-node-role here (every pod on the node); IRSA on real EKS |
| What would I have to change to move to another cloud? | Almost everything - ECS, task roles, ALB are AWS-only | The manifests move; IAM roles, VPC, node groups and LB annotations do not |

**For USMS I would choose ECS (Fargate).** It is a small team with one service that is quiet most of the year, and ECS + Fargate gave me scaling, a load balancer and no servers to patch with far fewer moving parts. Kubernetes would only win if USMS grew into many services or needed to run outside AWS.

## Exercise 5 Part 3 - what Lab 08 needs from configs/lab-07.env
- USMS_EKS_CLUSTER - every aws eks call and the kubeconfig context.
- USMS_EKS_NODEGROUP - Lab 08 changes the node group's scaling config from the AWS side.
- USMS_EKS_NAMESPACE - every kubectl command in Lab 08 runs in namespace usms.
- USMS_EKS_LB_PORTS (8081,8082) - Lab 08 can't publish a LoadBalancer/Ingress on Floci without it.
- USMS_EKS_ENDPOINT - check kubectl points at the right cluster (port 6500), especially after a rebuild.
- USMS_K8S_DEPLOY_ENROLMENT - the Deployment the HorizontalPodAutoscaler will target.
- USMS_K8S_DEPLOY_GATEWAY / USMS_K8S_SVC_GATEWAY - the Service that becomes NodePort, LoadBalancer and Ingress.
- USMS_K8S_CPU_REQUEST (50m) - to check the HPA's percentage maths by hand.
- USMS_K8S_MANIFEST_DIR - to rebuild everything quickly if Floci is restarted (Step 22 showed why).
The IAM role and policy ARNs are for the record and for cleanup; Lab 08 doesn't need them.

## Step 3 - "EKS is just ECS with different names"

**False:** on EKS the data plane is mine to run and pay for. The worker nodes are EC2 instances in my account, with a kubelet, a container runtime and the CNI plugin that I have to patch and upgrade (and the node group needs its own IAM role). On ECS with Fargate that whole column is almost empty - AWS runs the hosts.

**Nearly true:** both do the same basic job. I declare a container spec (task definition vs pod template), say how many copies I want (ECS service vs Deployment/ReplicaSet), and the platform keeps them running behind a stable name and replaces them during a rolling update.

## Floci notes recorded during the lab

- Step 8: the first create-cluster timed out because Floci was pulling rancher/k3s:latest (243 MB) during the request, and the CLI retried every ~60 s. Pre-pulling the image with `docker pull` fixed it.
- Step 9: OIDC issuer = None. The issuer is the URL that IAM would trust so Kubernetes ServiceAccounts can get AWS credentials (IRSA).
- Step 9: resourcesVpcConfig.vpcId came back empty; describe-cluster says 1.30 but kubectl shows v1.34.1+k3s1; endpoint is https://localhost:6500.
- Step 10/11: node group says desired 2, but there is 1 node (the k3s container).
- Step 16 "Your turn": the replacement pod was created by the ReplicaSet usms-enrolment-6965b8dbbb, not by the Deployment and not by me.
- Step 17: a Secret is base64, not encrypted. `kubectl set env --from=secret` on kubectl 1.34 added two secretKeyRef env entries instead of one envFrom.secretRef.
- Step 18 "Your turn": the new image nginx:1.27 took 3 minutes to pull, so rollout status timed out, but both old pods kept serving. With 2 replicas the default 25%/25% rounds to maxUnavailable 0 / maxSurge 1, so usms-results rolled out the same way as usms-enrolment.

## Step 21 - which IRSA steps worked

1. OIDC issuer published: no (None).
2. OIDC provider registered in IAM: no - nothing to register.
3. Web-identity role: not created - it needs the provider.
4. ServiceAccount: usms-enrolment-sa created, but there is no role ARN to annotate it with.
5-6. Webhook injecting the token / SDK calling AssumeRoleWithWebIdentity: not available.
So every pod gets the node role's permissions, including USMSStudentDataReadWrite.

## Step 22 - persistence

The EKS cluster and node group records survived a Floci restart, but Floci removed the k3s container ("Stopped k3s container" in the log) and never restarted it, so all Kubernetes objects were lost. Restarting only the k3s container with `docker restart` kept every object, so the limitation is Floci's, not Kubernetes'. I rebuilt from templates/ and manifests/lab-07/ in about a minute.

## Section 11 for my build

- Observed: Kubernetes objects, DNS discovery, load spreading, self-healing, rolling update and rollback, three failure modes, PDB blocking eviction, Kubernetes state surviving a container restart.
- Recorded only: IAM roles and policies, node group size and instance type, cluster SG, _lb_ports_ tag.
- Conceptual: IRSA, KMS encryption of Secrets, access entries, control-plane logging, pod IPs from the VPC.

## Review Questions

### Q1. ACTIVE cluster, every pod Pending

ACTIVE only describes the control plane - the API server and etcd that AWS runs. Pods don't run on the control plane on EKS; they run on the data plane, the worker nodes, and the scheduler can only place a pod on a node that has joined the cluster and has room. So both can be true at once: the API is healthy and accepts my Deployments, but nothing can run them. Two configurations that cause this: (1) no node group at all, or a node group whose nodes never joined (for example a node role missing eks:DescribeCluster, or nodes in a subnet with no route to the endpoint); (2) pods that can't fit or can't match - requests bigger than any node (like my usms-toobig pod), or a nodeSelector / taint the nodes don't satisfy. `kubectl describe pod` shows FailedScheduling with the reason in each case.

### Q2. Swapping the two trust policies

The cluster role would trust ec2.amazonaws.com and the node role would trust eks.amazonaws.com. Then the EKS control plane couldn't assume its role, and EC2 instances couldn't assume theirs. On real AWS I'd notice at Step 8: create-cluster would fail because EKS can't assume the cluster role (or at the latest, the cluster would never become ACTIVE). If I somehow got past that, Step 10's node group would fail because the instances couldn't get credentials, so nodes would never register and `kubectl get nodes` in Step 11 would be empty. On Floci none of this shows up, because trust policies are stored but not enforced - which is why the lab checks the Principal by reading it back.

### Q3. Readiness probe vs liveness probe

A readiness probe decides whether a pod is in the Service's endpoints and gets traffic; failing it just takes the pod out of rotation (Exercise 3's pods were Running but 0/1 and got no traffic). A liveness probe decides whether the container is alive; failing it makes the kubelet kill and restart the container. If you get them backwards and put a load-sensitive check (for example "can I reach the database quickly?") on the liveness probe, then during a busy period or a slow database every pod fails the check and gets restarted at the same time, so a slowdown turns into a full outage and a restart loop. That check belongs on readiness, which would only stop sending traffic until things recover.

### Q4. Why the pod still said 1.1.0 after the rollback

`kubectl rollout undo` only switched the Deployment back to the previous ReplicaSet's pod template. The version number came from the ConfigMap usms-app-config, which is a separate object that the rollback doesn't touch, and it was still at 1.1.0, so the "old" pods started with the new config. For the argument that "Kubernetes rollback is not really a rollback": it only reverts the Deployment, not the configuration, Secrets or anything else a release changed, so if a bad release was a config change, undo does nothing. Against: it does exactly what it promises and reverts the workload instantly, and rolling back config is a different job. The practice that solves it is to version configuration together with the workload - keep all manifests in Git and roll back by re-applying an earlier commit, or give each release its own ConfigMap name (e.g. usms-app-config-v2) so that the pod template itself points at the config and undo reverts both.

### Q5. maxUnavailable 0 vs the default, with two replicas

usms-enrolment has maxUnavailable 0 / maxSurge 1: it starts one new pod, waits for it to be ready, then removes an old one, so it never has fewer than 2 ready pods. usms-results uses the default 25% / 25%. With 2 replicas, Kubernetes rounds maxUnavailable down (0.5 → 0) and maxSurge up (0.5 → 1), so in my lab it actually behaved the same - my watch output showed 2 Running plus 1 new pod. The difference only shows with 4 or more replicas, where 25% lets one pod be down. maxUnavailable 0 suits something like enrolment that must never lose capacity during a release; the default suits a less critical service where a slightly faster roll that may drop capacity briefly is fine. maxUnavailable 0 / maxSurge 1 is closest to Lab 04's ECS settings of minimumHealthyPercent 100 / maximumPercent 200.

### Q6. "A Secret is encrypted, so it's fine to commit the manifest"

That's wrong. A Secret's values are only base64-encoded, which anyone can reverse - in Step 17 I decoded the token with one `base64 -d`. Committing the manifest puts the value in Git history forever. What a Secret does give you: the value is kept out of the container image, it can have separate RBAC from ConfigMaps (who can `get secrets`), and `kubectl describe` doesn't print it. What it doesn't give: any confidentiality from someone who can read the manifest, read the Secret through the API, or exec into the pod (inside the container it's plain text). On real EKS I would enable KMS envelope encryption for Secrets in etcd, keep real secrets in AWS Secrets Manager (pulled in with the Secrets Store CSI driver or External Secrets), give pods AWS access through IRSA instead of stored keys, and never commit Secret manifests - which is why I generated mine into outputs/.

### Q7. ECS or Kubernetes for USMS

For USMS - a small team, one region, quiet for eight months and very busy for two - I would choose ECS on Fargate. This lab made several things harder than Lab 04: I had to manage two IAM roles and a node group instead of one task role, write and order several YAML manifests per service, deal with nodes and their capacity (FailedScheduling, a single node), learn a second tool (kubectl) next to the AWS CLI, and on Floci even rebuild the whole cluster after a restart. ECS gave the same "keep 2 copies running behind a stable name" with fewer moving parts and no servers to patch. What Kubernetes gave me that ECS couldn't: built-in service discovery between my own services by DNS name (the gateway routed to three services without any load balancer), a portable set of manifests that would run on any Kubernetes cluster, and fine-grained tools like PodDisruptionBudgets. If USMS grew into many services, or needed to run outside AWS, those would tip the decision towards Kubernetes.