# Lab 08 – files prepared in advance (unzipped into the repo)

| File | Used in | Notes |
|---|---|---|
| manifests/lab-08/10-hpa-enrolment.yaml | Step 8 | lab label "08" (lab page says "05b") |
| manifests/lab-08/20-loadgen.yaml | Step 9 | |
| manifests/lab-08/30-pdb-gateway.yaml | Step 12 | replaces Lab 07 Ex 4's usms-enrolment-pdb (minAvailable 1 -> maxUnavailable 1) |
| manifests/lab-08/40-service-nodeport.yaml | Step 14 | |
| manifests/lab-08/50-service-loadbalancer.yaml | Step 15 | full Service manifest, not a patch |
| manifests/lab-08/60-ingress.yaml | Step 16 | |
| manifests/lab-08/11-hpa-results.yaml | Exercise 1 | |
| labs/lab-08-eks-scaling/exercise-files/ex3-usms-reports-broken.yaml | Exercise 3 | applied exactly as given |
| scripts/utilities/hpa-watch.sh | Step 9 | |
| scripts/utilities/lab-08-add-nodeselector.py | Step 11 | replaces the lab's inline python, which cannot match my 20-enrolment.yaml (topologySpreadConstraints from Lab 07 Ex 4) |
| scripts/utilities/verify-lab-08.sh | Section 8.1 | .gitkeep fix on the "no secret is tracked" check |
| scripts/cleanup/lab-08-cleanup.sh | Section 8.2 | NOT RUN. Also removes Exercise 1's usms-results-hpa |

Generated live during the lab (not in the zip): configs/lab-08.env, outputs/lab-08-*.
