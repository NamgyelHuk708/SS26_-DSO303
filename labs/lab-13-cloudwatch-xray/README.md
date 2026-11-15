# AWS Practical Laboratory Report

**Tools used:** Floci 2.4.0 (local AWS emulator, Docker Compose, hybrid storage), AWS CLI v1, python3, Docker

**Support on this build:** CloudWatch Logs, metric filters, custom metrics, alarms, composite alarms and dashboards **supported – and evaluated**; Logs Insights **unsupported** (Step 23 took path B); X-Ray **unsupported** – `put-trace-segments` and `create-sampling-rule` return `UnknownOperationException`, so the trace documents were validated structurally.

---

## 1. Aim / Objective

The aim of this practical is to add observability to the USMS transcript pipeline in three layers: a log layer (an inventory of what already existed, retention on every USMS log group, a central log group and structured log events), a metric layer (two metric filters tested before deployment, custom metrics with dimensions, a least-privilege telemetry policy, an instrumented and traced notifier deployed through its alias), and a trace layer (X-Ray segments, subsegments, annotations and a sampling rule). On top sit a threshold alarm, an absence alarm, a composite alarm and a dashboard, and everything is proven to survive a restart.

## 2. Introduction

Logs are text and metrics are numbers; nothing turns one into the other automatically – a metric filter does. Metrics answer "how many, how slow", logs answer "what happened", and traces answer "where in this one request the time went". Alarms turn metrics into decisions, and the most important alarm decision is what missing data means: for latency, silence at 3am is fine; for notifications, silence *is* the incident.

### Key Features

- **Retention by design:** a log group is a unit of retention and access, not a unit of component
- **Metric filters:** tested with `test-metric-filter` before deployment; evaluated on ingestion, not retroactively
- **Dimensions are identity:** namespace + name + the complete dimension set; cardinality is cost
- **Least-privilege telemetry:** `PutMetricData` scoped by a `cloudwatch:namespace` condition; log ARNs ending `:*`
- **Deploy through an alias:** version 3 instrumented, version 4 traced, rollback in one call
- **Missing data as a decision:** `notBreaching` vs `breaching`, and a composite alarm so one incident is one page

## 3. Use Case

| Need | How it is met |
|---|---|
| Logs must not be kept forever by accident | retention on every USMS log group, including two the lab's own list missed |
| Count transcript notifications without changing code | `usms-notify-count` metric filter on the notifier's log group |
| Know per faculty how many transcripts were processed, and the total | `TranscriptsProcessed {Faculty,Stage}` and `{}` |
| Be told when notifications are slow | `usms-transcript-lag-high` (Maximum > 2 s, 2 of 3 minutes) |
| Be told when notifications **stop** | `usms-notify-silence` (Sum < 1 for 15 minutes, missing = breaching) |
| One incident, one page | `usms-transcript-pipeline-down` = lag-high OR silence |
| Join a log line to a trace | the trace ID inside every `USMS_EVENT` line |

## 4. System Architecture / Design

![Lab 13 architecture](LAB_13(image)/architecture.png)

An upload to `usms-student-data` (1) triggers the notifier through alias `live` (2), which writes its log line and publishes its own metrics to CloudWatch (3), reads the object (4) and would send trace segments (5). The emitter script (6) writes all three signals for a fictional transcript. The panels show the three layers; the composite alarm's action (7) belongs to a future alerting lab. The notifier carries its real execution role with `USMSObservabilityWrite`, and the simulator evaluates that role's S3, CloudWatch and X-Ray permissions; the upload path returns 200.

## 5. Implementation Procedure

I probed the build (Insights and X-Ray unsupported) and took an inventory: nine log groups, all but one without retention, including `/ecs/usms-enrolment` (where the ECS tasks really log) and Lab 11's CodeBuild groups. I created the central log group and set retention on every USMS group, wrote structured events (from a JSON file – the lab's shorthand command cannot carry JSON), tested both filter patterns and deployed them, and proved the notifier's filter end to end with a real upload. I published custom metrics with and without dimensions, created `USMSObservabilityWrite` and attached it to two roles (by name – `lab-01.env` stores ARNs), deployed the instrumented notifier as version 3 through the alias, rolled back and forward, and published version 4 with active tracing. I built the X-Ray documents and validated them structurally, fixed the emitter (two bugs), created the three alarms, proved them both by forced transitions and by real data, built the dashboard, queried the logs (path B), restarted Floci and compared everything, wrote `configs/lab-13.env`, verified and committed.

## 6. Results and Evidence

### 6.1 CLI Output

Environment

![Step 1](LAB_13(image)/1.png)

*Floci up; verify-lab-10 51/0; every env file sourced*

---

Names, probe and inventory

![Steps 2–5](LAB_13(image)/2.png)

*Role names derived from ARNs; alias live → 1; Insights and X-Ray UNSUPPORTED; nine log groups, retention None almost everywhere*

---

Retention on every USMS group

![Step 6](LAB_13(image)/6.png)

*8 groups set, including /ecs/usms-enrolment and the two CodeBuild groups the lab's list misses; tags read back Lab=13*

---

Structured events

![Step 7](LAB_13(image)/7.png)

*The lab's shorthand failed ("Expected ',', received '\"'"); 4 events written from a JSON file, plus the non-matching health-check line*

---

Testing patterns before deploying them

![Step 8](LAB_13(image)/8.png)

*USMS_NOTIFY matches 1 of 4; plain ERROR also matches "no ERROR here", the quoted phrase does not*

---

Two metric filters

![Step 9](LAB_13(image)/9.png)

*Each filter on the right log group*

---

The filter proven end to end

![Step 10.1](LAB_13(image)/10.1.png)

*The upload reached the notifier through the S3 notification; USMS_NOTIFY lines in the log group*

---

![Step 10.2](LAB_13(image)/10.2.png)

*NotifyCount Sum 2, SampleCount 4 (2 matches + 2 default zeroes); CentralErrorCount empty – not retroactive; then 1 for a new ERROR line*

---

Custom metrics and dimensions

![Step 11](LAB_13(image)/11.png)

*TranscriptsProcessed three times (science, engineering, total); TranscriptLagSeconds SampleCount 2 / Max 1.91; asking without the dimension → 0*

---

USMSObservabilityWrite

![Step 12](LAB_13(image)/12.png)

*Three statements; attached to usms-lambda-exec-role and usms-ec2-app-role*

---

The instrumented notifier

![Step 13.1](LAB_13(image)/13.1.png)

*Environment read before replacing it; version 3; live → 3*

---

![Step 13.2](LAB_13(image)/13.2.png)

*trace_id and seconds in the payload; metric_published true – the function publishes its own metric (Faculty=evidence)*

---

Active tracing

![Step 14](LAB_13(image)/14.png)

*Version 4 Active while version 3 stays PassThrough; the trace id is still a request id – no trace started*

---

The parent segment

![Step 15](LAB_13(image)/15.png)

*Trace id 1-6af9c034-…; put-trace-segments → UnknownOperationException*

---

Subsegments and structural validation

![Step 16](LAB_13(image)/16.png)

*10 of 10 structural checks*

---

The emitter

![Step 17](LAB_13(image)/17.png)

*First run: the log line failed (shorthand again) and the metrics landed in USMS/Enrolment*

---

![Step 17 fixed](<LAB_13(image)/17(fix).png>)

*Namespace collision with Lab 6 fixed (USMS_APP_METRIC_NAMESPACE), log line sent as JSON; the trace id found inside the log line*

---

Sampling rule

![Step 18](LAB_13(image)/18.png)

*All 11 fields; create-sampling-rule → UnknownOperationException*

---

![Step 18 fixed](<LAB_13(image)/18(fix).png>)

*The document as the deliverable*

---

Two alarms

![Step 19](LAB_13(image)/19.png)

*notBreaching vs breaching – the point of the step in one column*

---

A forced transition

![Step 20](LAB_13(image)/20.png)

*OK → ALARM → OK with reasons; history shows Floci itself had moved the alarm INSUFFICIENT_DATA → OK first*

---

Alarm evaluation on real data

![Step 20.2](LAB_13(image)/20.2.png)

*4.20 s and 3.70 s in consecutive minutes → lag-high ALARM by itself ("2 datapoint(s) breaching the threshold")*

---

![Step 20.3](LAB_13(image)/20.3.png)

*Back to OK by itself once the points aged out; the composite followed both ways*

---

The composite

![Step 21](LAB_13(image)/21.png)

*Rule returned as written; a child forced to ALARM drives the parent to ALARM*

---

The dashboard

![Step 22](LAB_13(image)/22.png)

*No validation messages; 5 widgets, 24 columns, no overlap*

---

Querying the logs (path B)

![Step 23](LAB_13(image)/23.png)

*science 6, engineering 5 – parsed on the laptop because Insights is absent*

---

Restart

![Step 24.1](LAB_13(image)/24.1.png)

*Inventory before*

---

![Step 24.2](LAB_13(image)/24.2.png)

*CONFIGURATION IDENTICAL; data before = after (NotifyCount 2, Lag 5, 12 events)*

---

The absence alarm

![Step 24.3](LAB_13(image)/24.3.png)

*usms-notify-silence ALARM at 14:50 by itself (3 empty buckets); three uploads → NotifyCount 3 → OK, composite OK*

---

configs/lab-13.env

![Step 25](LAB_13(image)/25.png)

*28 exports; versions 3 and 4; both namespaces coexist in one shell*

---

Verification

![Section 8](LAB_13(image)/26.png)

*PASS=49 FAIL=0 after fixing the verify script; Lab 10 51/0; Lab 06 24/18 (its Path C count was 23/19)*

### 6.2 AWS Console Verification

Floci has no console and nothing renders the dashboard. Everything was verified by readback (`describe-*`, `get-metric-statistics`, `describe-alarm-history`, `get-dashboard`) and by the log groups themselves. On real AWS the same evidence would be the CloudWatch console's log groups, metrics browser, alarm history and rendered dashboard, and the X-Ray trace map.

## 7. Analysis and Discussion

**What Floci 2.4.0 actually did.** The lab expected metric filters, alarms and composites to be stored but not evaluated. On this build they were evaluated:

| Behaviour | Evidence |
|---|---|
| S3 → Lambda delivery | the upload of `lab-13-probe-object.json` ran the notifier (Lab 10 recorded delivery as missing) |
| Metric filter on ingestion | NotifyCount Sum 2 / SampleCount 4; a new ERROR line counted; old lines not (not retroactive) |
| Alarm evaluation | lag-high: OK by itself, ALARM by itself on real breaching data, OK again as the points aged out |
| Absence alarm | silence: OK while the 14:15 bucket was in its window, ALARM at 14:50 after three empty buckets, OK after transcripts flowed |
| Composite evaluation | followed its children both when forced and when driven by data |
| Persistence | configuration and data identical across a restart |

My own first reading of the absence alarm was wrong: I recorded it as "never fires" at 14:41, before its 15-minute window had passed – exactly the premature judgement Step 20 warns about. The history later showed Floci had been right all along.

**Bugs found and fixed.**

| Where | Problem | Fix |
|---|---|---|
| Step 7 and the emitter | `--log-events timestamp=…,message='USMS_EVENT {"…"}'` cannot pass quotes and commas through CLI shorthand; nothing was written | events sent as a JSON file |
| Step 17 | `lab-06.env` exports `USMS_METRIC_NAMESPACE=USMS/Enrolment`; the emitter inherited it and published into Lab 6's namespace (metrics cannot be deleted); the lab's `lab-13.env` would have broken `verify-lab-06.sh` | `USMS_APP_METRIC_NAMESPACE` |
| Steps 12, 14, verify | `lab-01.env` stores role ARNs, the commands take role names | `${VAR##*/}` |
| verify-lab-13.sh | `Metrics[].join(...) \|\| 'NONE'` applies `\|\|` to the list, so a dimensionless metric is `""`, never `NONE` | `length(Metrics[?length(Dimensions)==\`0\`])` |
| verify-lab-13.sh | `--filter-name-prefix` without `--log-group-name` | added |
| Step 6 | the retention list and verify regex miss `/ecs/usms-enrolment` and `/aws/codebuild/usms-*` | added to the list |

**Observed, recorded, not available.**

| Observed | Recorded only | Not available |
|---|---|---|
| retention, structured events, filter testing and evaluation, custom metrics and dimensions, function-published metrics, alias rollback, alarm and composite evaluation, forced transitions and history, dashboard document, restart persistence | IAM enforcement of `USMSObservabilityWrite`; `TracingConfig Active` (stored, no trace started); the sampling rule; the segment documents | X-Ray API, Logs Insights, AWS-published metrics, a rendered dashboard, alarm actions (SNS), cost |

## 8. Reflection

**What I learned.** That an alarm's missing-data setting is a design decision, and that the absence alarm is the valuable one: on this build I watched it fire after fifteen silent minutes and clear when transcripts flowed again. I also learned that metric identity includes the full dimension set, that a filter pattern is not a regular expression, and that `defaultValue` is per non-matching event, not per empty period.

**Challenges.** The hardest moment was being wrong twice in one afternoon – once about the silence alarm (judged before its window had passed) and once about Lab 6 (its scaling checks were already failing on Path C, not lost). Both were caught by reading the alarm history and the earlier lab's own report instead of assuming. The variable-name collision with Lab 6 was the most instructive bug: two labs, one name, two meanings.

**Real-world use.** I would set retention when a log group is created, test every filter pattern, publish totals explicitly, keep student IDs out of dimensions, alarm on silence as well as on thresholds, and page only on the composite.

## 9. Conclusion

The transcript pipeline now has retained logs, evaluated metric filters, custom metrics with deliberate dimensions, a least-privilege telemetry policy, an instrumented notifier deployed and rolled back through its alias, three alarms proven both by forced transitions and by real data, and a dashboard – all surviving a restart, with `verify-lab-13.sh` at 49 of 49. X-Ray is not available on this build; its documents were built and validated structurally.

## 10. Appendix

### Additional Files

- `labs/lab-13-cloudwatch-xray/transcript-notifier-v2/notifier.py`, `labs/lab-13-cloudwatch-xray/exercises.md`
- `policies/usms-observability-write-policy.json`
- `templates/lab-13-metric-data.json`, `lab-13-segment-parent.json`, `lab-13-segment-subsegments.json`, `lab-13-segment-downstream.json`, `lab-13-sampling-rule.json`, `lab-13-dashboard.json`
- `scripts/utilities/usms-emit-telemetry.sh`, `verify-lab-13.sh`; `scripts/cleanup/lab-13-cleanup.sh` (not run)
- `configs/lab-13.env`, `notes/lab-13-notes.md`
- Simulator: `USMS Lab 13 - CloudWatch and X-Ray.json`

### Submission Checklist

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