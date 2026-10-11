# Lab 04 Notes

**Floci support path (Step 3): B - ECS only.**

- ECS is supported. The `describe-services` probe failed only because the
  cluster "probe" does not exist (`ClusterNotFoundException: Cluster not found: probe`),
  not because the API is missing.
- CloudWatch and CloudWatch Logs are supported.
- Application Auto Scaling is NOT supported in this Floci build:
  `UnknownOperationException: Unknown operation: AnyScaleFrontendService.DescribeScalableTargets`.
  The same applies to describe-scaling-policies and describe-scheduled-actions.

This does not affect Lab 04, which only uses ECS. It will matter in Lab 06,
which uses the documented fallback for Path B.

