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
