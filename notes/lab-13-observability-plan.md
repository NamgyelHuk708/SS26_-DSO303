# USMS Observability Plan – transcript delivery

*Lab 13 Exercise 4. A design document: no commands. Every number says where it came from.*

## 1. The registrar's four complaints, by layer

| Complaint | Right layer | Why not the other two |
|---|---|---|
| "Nobody noticed for six hours that transcripts had stopped – the dashboard was green because the graphs were empty." | **Metrics, with an alarm on absence** | Logs record what happened; when nothing happens they record nothing, so no log search fires on silence. A trace exists only for a request that ran. Only a metric alarm can treat *no data* as a signal (`treat-missing-data breaching`). |
| "We could not tell whether it was the upload, the function or the bucket." | **Traces** | A metric says *that* transcripts were slow or missing, for everyone at once; a log line says what one component did, with no link to the others. A trace follows one request across S3 → notifier → bucket and shows which segment failed or faulted (`service("usms-student-data") { fault }`). |
| "The audit office asked who downloaded a transcript in March, and the logs were gone." | **Logs, retained for audit** | A metric aggregates away *who*; traces are kept 30 days and are sampled (my rule keeps 2/s plus 10%), so an audit question about one access in March cannot rely on them. Only a complete, long-retained access log can answer it. |
| "Our monitoring bill is larger than the thing being monitored." | **All three – it is a cost design problem** | Cost comes from ingested log GB, the number of metrics (cardinality), and traces; each layer has its own lever (Section 5). |

## 2. Log group taxonomy

A log group is a unit of retention and access control, not a component (Lab 13 Step 6).

| Group | Holds | Retention | Readers |
|---|---|---|---|
| `/usms/central/application` | structured application events from every compute tier | 30 days | developers, on-call |
| `/usms/ecs/enrolment`, `/ecs/usms-enrolment` | container output | 30 days | developers, on-call |
| `/aws/lambda/usms-*` | function runtime output | **14 days** – the shortest | developers |
| `/aws/codebuild/usms-*` | build logs | 14 days | developers |
| **`/usms/audit/transcript-access`** | one event per transcript access: who, which object, when, from where (sourced from S3 data events via CloudTrail) | **2557 days (7 years)** – the longest | **audit office only**, read-only; no developer access |

**Longest:** 7 years, because academic records and their access history are typically kept for years after graduation. This number must be confirmed with the registrar against the university's records-retention policy – it is the one figure here I would not choose myself. **Shortest:** 14 days for function output, because it is debugging data: if nobody looked at it within two weeks, nobody will (Lab 13 Step 6). The audit group is separate so its long retention does not apply to the high-volume debugging logs, and so its readers can be restricted with a resource-level policy on that one group.

## 3. Service level indicators

An SLI is something a student would notice.

| SLI | Target | Alarm or graph |
|---|---|---|
| **Delivery success**: transcripts notified ÷ transcripts uploaded | 99.5 % per day | **Alarm** – failures directly harm a student |
| **Delivery latency**: p99 seconds from upload to notification | under 2 s (the `usms-transcript-lag-high` threshold, from my observed baseline of 0.38–0.51 s for normal transcripts) | **Alarm** on Maximum (Step 19), graph p99 |
| **Freshness**: minutes since the last notification during working hours | under 15 min | **Alarm** – this is `usms-notify-silence` |

The 99.5 % target is "it seemed reasonable", stated honestly: before committing to it I would measure a month of real success rates. Graph-only SLIs are not wasted: they show trends before they become incidents (latency creeping up week by week), and they answer "was it already bad before the change?" during an incident.

## 4. Alarms and missing data

| Alarm | Metric | Missing data | Why |
|---|---|---|---|
| `usms-transcript-lag-high` | TranscriptLagSeconds Maximum > 2 s, 2 of 3 minutes | `notBreaching` | no transcripts at night means no latency data, and that is normal |
| **`usms-notify-silence`** | NotifyCount Sum < 1 for 3 × 5 minutes | **`breaching`** | the absence **is** the incident |
| `usms-delivery-failures` (new) | CentralErrorCount Sum ≥ 5 in 5 min, from the `"ERROR USMS_EVENT"` phrase filter | `notBreaching` | no errors logged is good news |
| `usms-transcript-pipeline-down` | composite: any of the above | – | **the only one that pages** |

**The one that would have caught the six-hour outage is `usms-notify-silence`** – and I saw it work: after three empty five-minute buckets Floci moved it to ALARM, and three uploads cleared it. A threshold alarm on a *value* could not catch it: during the outage there are no values, so `TranscriptLagSeconds` has no data, `notBreaching` reads that as fine, and lag-high stays green – exactly the "all green while empty" dashboard the registrar described. During working hours the silence window should be 15 minutes; at night it should be suppressed (a composite with `NOT ALARM(...)` on a schedule-driven alarm), or it pages every night.

## 5. Where the bill goes, and the two biggest levers

Order-of-magnitude estimate for USMS (to be checked against a month of real usage before committing):

| Item | Driver | Relative size |
|---|---|---|
| Log ingestion | GB/day of container and function output | **largest** – debug-level logging from every task |
| Custom metrics | number of distinct metric + dimension combinations | medium – grows with cardinality |
| Logs Insights queries | GB scanned per query | spiky – one month-long `@message` query can rival a day of ingestion |
| Traces | traces recorded | small with sampling |
| Alarms, dashboards | count | small |

**Two biggest levers:** (1) **retention and log level** – set retention on every group (the course created groups with none) and log at INFO, not DEBUG, in production; (2) **cardinality** – keep high-cardinality values out of dimensions.

**Cardinality of every proposed dimension:** `Faculty` ≈ 8 values; `Stage` ≈ 3 (notify, origin, viewer-request); `Faculty × Stage` ≤ 24 metrics for `TranscriptsProcessed`. **Rejected as a dimension:** student id (~30,000 values → 30,000 metrics); it belongs in log fields and trace annotations. My own Lab 13 data shows the risk is real: the notifier derives `Faculty` from the S3 key, and `transcripts/evidence/…` produced a new value, `evidence` – a path-derived dimension grows whenever someone invents a folder.

## 6. What I would not build yet

**Anomaly-detection alarms.** They need weeks of history to learn a baseline; with a few days of data they would page on normal variation (enrolment weeks are not like other weeks). **The observation that would change my mind:** a month of `TranscriptsProcessed` data showing a regular weekly pattern that a fixed threshold either misses or over-alerts on.

## 7. What I would measure before committing

- a month of real transcript volume per faculty (the SLO targets and the silence window depend on it)
- the actual GB/day per log group (the cost estimate)
- the latency distribution under enrolment-week load (whether 2 s is the right threshold or just the one I chose from five data points)
