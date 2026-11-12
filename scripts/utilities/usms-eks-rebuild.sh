#!/usr/bin/env bash
# Rebuild the Lab 07 / Lab 08 Kubernetes state after a Floci restart.
#
# Why this exists: on this Floci build a floci-down / floci-up recreates the k3s cluster
# behind usms-eks-cluster EMPTY (Lab 07 Step 22, Lab 08 Step 0). The AWS records survive;
# every Kubernetes object does not. Everything is in manifests/, so this re-applies it.
#
# What it changes: ~/.kube/config (backed up first) and the usms namespace in the k3s cluster.
# It does NOT touch anything on the AWS side. Safe to run more than once.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"
CTX=usms-eks-k3s
KCFG=outputs/lab-08-kubeconfig.yaml

echo "== 1. wait for the k3s container =="
CTR=""
for i in $(seq 1 36); do
  CTR=$(docker ps --format '{{.Names}}' | grep 'eks-usms-eks-cluster' | head -1)
  [ -n "$CTR" ] && break
  sleep 5
done
[ -n "$CTR" ] || { echo "no k3s container after 3 minutes - is Floci up? (docker ps)"; exit 1; }
echo "found $CTR"

echo "== 2. fresh admin kubeconfig as context $CTX =="
for i in $(seq 1 24); do
  docker exec "$CTR" test -s /etc/rancher/k3s/k3s.yaml 2>/dev/null && break
  sleep 5
done
docker exec "$CTR" cat /etc/rancher/k3s/k3s.yaml \
  | sed -e 's#https://127.0.0.1:6443#https://localhost:6500#' -e "s/default\$/$CTX/" > "$KCFG"
chmod 600 "$KCFG"
cp ~/.kube/config ~/.kube/config.bak-rebuild-$(date +%Y%m%d%H%M%S)
kubectl config delete-context "$CTX" >/dev/null 2>&1 || true
kubectl config delete-cluster "$CTX" >/dev/null 2>&1 || true
kubectl config unset "users.$CTX"   >/dev/null 2>&1 || true
KUBECONFIG=~/.kube/config:"$KCFG" kubectl config view --flatten > /tmp/kc-merged-$$ \
  && mv /tmp/kc-merged-$$ ~/.kube/config && chmod 600 ~/.kube/config
kubectl config use-context "$CTX"

echo "== 3. wait for the API and the node =="
for i in $(seq 1 36); do
  kubectl get nodes --no-headers 2>/dev/null | grep -q ' Ready' && break
  sleep 5
done
kubectl get nodes -L workload,tier
for N in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
  kubectl label node "$N" workload=usms tier=app --overwrite >/dev/null
done

echo "== 4. re-apply Lab 07 and Lab 08 from manifests/ =="
kubectl apply -f manifests/lab-07/00-namespace.yaml
kubectl config set-context --current --namespace=usms >/dev/null
kubectl apply -f manifests/lab-07/
[ -f outputs/lab-07-secret.yaml ] && kubectl apply -f outputs/lab-07-secret.yaml \
  && kubectl set env deployment/usms-enrolment --from=secret/usms-enrolment-secret
for f in manifests/lab-08/*.yaml; do
  case "$f" in *20-loadgen.yaml) continue;; esac   # the load generator is not kept (Lab 08 Section 15)
  kubectl apply -f "$f"
done

echo "== 5. wait and check =="
for d in usms-enrolment usms-results usms-gateway usms-timetable; do
  kubectl rollout status deployment/"$d" --timeout=240s
done
kubectl get deploy,hpa,pdb,svc,ingress
kubectl run usms-smoke --rm -i --restart=Never --image=busybox:1.36 -- sh -c '
  G=http://usms-gateway.usms.svc.cluster.local
  wget -qO- $G/ && wget -qO- $G/enrolment/ && wget -qO- $G/results/' && echo "SMOKE TEST PASSED"
