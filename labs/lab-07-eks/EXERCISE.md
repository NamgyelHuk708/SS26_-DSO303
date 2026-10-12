# Lab 7 Independent Exercises

---

## Exercise 1: A Fourth Microservice (usms-timetable)

### What I did
I wrote `manifests/lab-07/70-timetable.yaml` by hand, based on `30-results.yaml`. It has three objects in one file:
- **ConfigMap `usms-timetable-conf`:** an nginx template that returns JSON with the service name, pod name, campus and version, plus `/healthz`
- **Deployment `usms-timetable`:** 1 replica, `nginx:1.27-alpine`, CPU/memory requests (50m / 32Mi) and limits, a readiness probe on `/healthz`, and the same labels as the others (`app`, `project`, `tier`)
- **Service `usms-timetable`:** ClusterIP on port 80

I checked it with `kubectl apply --dry-run=client` before applying it for real.

![Exercise 1 - dry run, apply, rollout](LAB_07(image)/ex1.1.png)

### Result
- Four Deployments and four Services in namespace `usms`; `usms-timetable` 1/1 on ClusterIP `10.43.81.232`
- A busybox pod fetching `http://usms-timetable.usms.svc.cluster.local/` got:
  `{"service":"usms-timetable","pod":"usms-timetable-cf6b9c8fb-kjlpb","campus":"rtc","version":"1.0.0"}`

![Exercise 1 - four services and the JSON response](LAB_07(image)/ex1.2.png)

---

## Exercise 2: Route to It, and Prove the Route

### What I did
I added a `location /timetable/` block to `manifests/lab-07/40-gateway.yaml` that does `proxy_pass http://usms-timetable.usms.svc.cluster.local/`, and added `/timetable/` to the routes list in the root response. I edited the file and re-applied it; I didn't use `kubectl edit`.

![Exercise 2 - the new block and the dry run](LAB_07(image)/ex2.1.png)

### Which command made the change reach the pod
| After | ReplicaSets | Revisions |
|---|---|---|
| `kubectl apply -f 40-gateway.yaml` | only `58854c9ffd` (ConfigMap `configured`, Deployment `unchanged`) | 1 |
| `kubectl rollout restart deployment/usms-gateway` | new `54559f9b7f` (1) + old `58854c9ffd` (0) | 2 |

Changing only the ConfigMap left the pod template unchanged, so `apply` created no new ReplicaSet and the running nginx still had the old configuration (the same lesson as Step 18). Of the two ways to roll pods from Step 18, only **`kubectl rollout restart`** fits, because nothing in the pod template itself changed. It adds a restart timestamp to the template, which creates the new ReplicaSet.

![Exercise 2 - same ReplicaSet after apply, new one after restart](LAB_07(image)/ex2.2.png)

### Proof, in one command
All four paths through the gateway answered:
- `/` → gateway, routes now `["/enrolment/","/results/","/timetable/"]`
- `/enrolment/` → usms-enrolment
- `/results/` → usms-results
- `/timetable/` → usms-timetable

![Exercise 2 - all routes working](LAB_07(image)/ex2.4.png)

---

## Exercise 3: Find the Misconfiguration

I applied the given `usms-broken` manifest exactly as written, then found the faults with commands, in this order:

| # | Command | What it showed |
|---|---|---|
| 1 | `kubectl get endpoints usms-broken` | `<none>` – the Service sends traffic nowhere |
| 2 | `kubectl get svc usms-broken -o jsonpath='{.spec.selector}'` | `{"app":"usms-broken","version":"v2"}` |
| 3 | `kubectl get pods -l app=usms-broken --show-labels` | pods have `version=v1` → **fault 1** |
| 4 | `kubectl get pods -l app=usms-broken` | both pods `0/1 Running` – never Ready |
| 5 | `kubectl describe pod -l app=usms-broken` | readiness probe `http-get …/healthz` → **fault 2** |

![Exercise 3 - diagnosis](LAB_07(image)/ex3.1.png)

### The two faults
- **Fault 1:** the Service selector requires `version: v2`, but the pod template labels the pods `version: v1`, so the selector matches no pods at all.
- **Fault 2:** the readiness probe checks `/healthz`, but plain `nginx:1.27-alpine` has no such page and returns 404. The pods never become Ready, and a Service never sends traffic to pods that aren't Ready.

### The fix
1. **The one-line fix:** change the Service selector from `v2` to `v1` (`kubectl patch svc … /spec/selector/version = v1`). After this, the endpoints were **still empty**, which proved there was a second, independent fault.
2. Change the readiness probe path from `/healthz` to `/` (plain nginx serves `/` with 200). The Deployment rolled out, both pods became `1/1`, and the Service got **two endpoints**: `10.42.0.31:80, 10.42.0.32:80`.

Then I deleted `usms-broken` (a CLEAN UP item), leaving the 6 normal pods.

![Exercise 3 - fixes and two endpoints](LAB_07(image)/ex3.2.png)

The lab asked for a fix that changes exactly one line, and the selector is that line, but on its own it doesn't make the Service work. The probe path also has to change; the alternative would be to serve `/healthz` from nginx, like the other three services do.

---

## Exercise 4: Survive a Node Going Away

### My cluster has one node
Floci runs the whole cluster as a single k3s container (node `b079e66285ea`), even though the node group says desired 2. So the requirement "not all capacity on one node" **can't be met here**. I said so, added the configuration that would meet it on a real cluster, and demonstrated what one node allows.

### What I changed
1. **`topologySpreadConstraints`** in `20-enrolment.yaml`: `maxSkew: 1` on `kubernetes.io/hostname`, `whenUnsatisfiable: ScheduleAnyway`. This is **advisory**: with two or more nodes, the scheduler puts the two enrolment pods on different nodes, but it still schedules them if that's impossible (as here). I chose `ScheduleAnyway` so pods start instead of staying Pending on a one-node cluster.
2. **A new object, `25-enrolment-pdb.yaml`:** a `PodDisruptionBudget` with `minAvailable: 1` for `app: usms-enrolment`. This is **enforced**: voluntary disruptions like `kubectl drain` are refused if they would leave fewer than one ready pod.
3. **"Which node is each pod on, from the cluster itself":** `kubectl get pods -l app=usms-enrolment -o wide` shows the NODE column.

![Exercise 4 - spread rule, PDB and pods with their node](LAB_07(image)/ex4.1.png)

### The demonstration
I drained the only node, limited to the enrolment pods (`--pod-selector=app=usms-enrolment`, so the rest of the app wasn't touched), while a smoke loop in a second terminal called `/enrolment/` through the gateway every second.

| What happened | Evidence |
|---|---|
| Node cordoned | `node/b079e66285ea cordoned` |
| First pod evicted | `pod/usms-enrolment-8549846ddd-h4vw4 evicted` |
| Second pod **blocked** | `Cannot evict pod as it would violate the pod's disruption budget.` – retried 7 times, blocked every time |
| During the drain | one pod Running, the replacement Pending (nowhere to go on a cordoned single node); PDB `ALLOWED DISRUPTIONS 0` |
| After `kubectl uncordon` | Pending pod scheduled, back to 2/2, node Ready |
| Smoke loop | **`OK` every second from 19:48:08 to 19:48:49, no FAIL** |

![Exercise 4 - drain blocked by the PDB, then uncordon](LAB_07(image)/ex4.2.png)

![Exercise 4 - smoke loop never failed](LAB_07(image)/ex4.3.png)

### Why these choices
The PDB is what guarantees "never below one healthy pod during a voluntary disruption" – the drain physically could not take the last pod, and the service never failed a request. The topology spread rule is what would guarantee "not all capacity on one node", but only when there are nodes to spread across; on real EKS with two nodes in two AZs, the pair of them would keep enrolment serving through a node drain or even the loss of an AZ. `-o wide` lets anyone check pod placement from the cluster at any time, not from memory. Note that a PDB only protects against *voluntary* disruptions; a node that crashes is not stopped by a PDB, which is why the spread rule (and two replicas) matter too.

---

## Exercise 5: Prepare What Lab 08 Needs

### Part 1 – CPU baseline (`outputs/lab-07-cpu-baseline.txt`)
The metrics API **is available** on this build (metrics-server runs in k3s), so `kubectl top` worked:

```
metrics API: available
cpu request per pod: 50m
usms-enrolment-8549846ddd-khc8p cpu=1m (2% of the 50m request) mem=9Mi
usms-enrolment-8549846ddd-pv7tq cpu=1m (2% of the 50m request) mem=9Mi
```

Idle nginx uses about 1m, which is 2% of the 50m request. Lab 08's HPA will compute utilisation as a percentage of that request.

![Exercise 5 - CPU baseline](LAB_07(image)/ex5.1.png)

### Part 2 – Lab 01's policy (`outputs/lab-07-lab06-readiness.txt`)
Read from the policy document with `get-policy` and `get-policy-version`, not from memory:

| Item | Value |
|---|---|
| Policy ARN | `arn:aws:iam::000000000000:policy/USMSStudentDataReadWrite` (default version v1) |
| Roles carrying it | `usms-ec2-app-role`, `usms-ecs-task-role`, `usms-eks-node-role` |
| Resources | Allow `arn:aws:s3:::usms-student-data` (the bucket, for ListBucket), Allow `arn:aws:s3:::usms-student-data/*` (the objects), Deny `arn:aws:s3:::usms-student-data` (the DeleteBucket deny) |
| Does the bucket exist? | **No** – `head-bucket` returned 404 Not Found, exit code 255. It is created in Lab 10 |

Both files were confirmed git-ignored with `git check-ignore -v`.

![Exercise 5 - policy readiness](LAB_07(image)/ex5.2.png)

### Part 3 – what Lab 08 needs from `configs/lab-07.env`
Added to `notes/lab-07-notes.md`: the cluster name, node group, namespace, `_lb_ports_` (8081,8082), endpoint, the enrolment and gateway Deployment/Service names, the 50m CPU request and the manifest directory (to rebuild quickly after a Floci restart). The IAM role and policy ARNs are for the record and cleanup only.

![Exercise 5 - notes for Lab 08](LAB_07(image)/ex5.3.png)

---

## Summary

| Exercise | Result |
|---|---|
| 1 | usms-timetable deployed from a hand-written manifest; 4 services answering |
| 2 | `/timetable/` route added by file; `rollout restart` was the command that created the new ReplicaSet; all routes proven in one command |
| 3 | Two faults found with commands (selector v2 vs v1, probe on a 404 path); fixing only one left zero endpoints |
| 4 | One node only, so spread is advisory here; the PDB blocked the second eviction and the smoke loop never failed |
| 5 | Metrics API available (1m = 2% of request); policy held by 3 roles, bucket still missing; Lab 08 variables listed |