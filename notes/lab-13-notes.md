## Floci 2.4.0 findings (short)
- S3 -> Lambda delivery worked; Lambda stdout reached /aws/lambda/usms-transcript-notifier.
- Metric filters evaluated on ingestion (not retroactive); defaultValue emitted per non-matching event.
- Alarms and composites evaluated on real data: lag-high OK -> ALARM -> OK; silence OK (14:15 bucket in window) ->
  ALARM 14:50 (3 empty buckets) -> OK after 3 uploads. My first reading of silence ("never fires") was premature.
- X-Ray: UnknownOperationException for PutTraceSegments and CreateSamplingRule. Insights unsupported (path B).
- Configuration and data survived floci-down/floci-up.
- Bugs fixed: CLI shorthand cannot carry JSON log messages; USMS_METRIC_NAMESPACE collision with Lab 6
  (-> USMS_APP_METRIC_NAMESPACE); role ARNs vs names; verify JMESPath total check; --filter-name-prefix needs a group.

## Review Questions

### Q1. "We have logs, so we do not need metrics"
First: a metric is cheap to read and cheap to alarm on - one number per period, kept for fifteen months, evaluated
by CloudWatch every period for almost nothing - while answering a numeric question from logs means scanning every
event in the window each time (Insights is billed per GB scanned; my path-B query downloaded every event to my
laptop). Second: alarms work on metrics, not on logs; to alarm on something in a log you must first turn it into a
metric (a metric filter), so "only logs" really means "no alarms", or alarms built on repeated scans. They are right
when the question is rare, exploratory or about one specific event ("what happened to stu-01044 at 14:15?") - a log
answers that and a metric cannot, and building a metric for a question asked once a year is waste.

### Q2. Metric filter vs put-metric-data
Retroactivity: neither is retroactive - a filter only sees events ingested after it exists (my Step 7 ERROR line
was never counted), and a direct metric only exists from the first publish; only a log query is retroactive. Cost:
a filter needs no code and no extra API calls, but its output is still a billed metric; put-metric-data costs an
API call per publish plus the metric. To add a measurement: a filter needs only a new pattern on existing log
lines (no deployment); a direct metric needs a code change and a deployment (my notifier v3). Code that is not
yours: only a filter works - you cannot add put_metric_data to someone else's code, but you can count what it logs.
"How many downloads happened": a filter - each download already logs a line, the count is a pattern match and
needs no code change. "How long the render took": put-metric-data from the code that timed it - the duration is
known precisely inside the function, a filter would need the value written into the log in a parseable position
(Exercise 1), and timing should not depend on a log format.

### Q3. notBreaching on lag, breaching on silence
On usms-notify-silence, notBreaching would mean an empty window counts as fine - the alarm watches for an absence,
so treating absence as fine means it can never fire; it would sit at OK through a six-hour outage. On
usms-transcript-lag-high, breaching would mean every quiet night (no transcripts, so no latency data) is treated
as slow, paging someone at 3am for nothing. The incident the silence alarm catches and lag-high cannot: the S3
notification is removed (a replace-only put-bucket-notification-configuration that forgot the Lambda), so the
notifier never runs - no latency data at all, so lag-high reads notBreaching and stays OK. During it the dashboard
would look calm: the latency graph empty (not red), the "notifications in 5 minutes" single value showing nothing,
the alarm widget green - only silence (and the composite) would be red. I watched the healthy half of this: silence
went to ALARM at 14:50 after three empty buckets and cleared when transcripts flowed.

### Q4. Dimension vs annotation
A metric dimension is part of the metric's identity, indexed for aggregation over time: every distinct combination
is a separate billed metric, kept fifteen months, and you can graph and alarm on it but not search for one event.
As distinct values grow, the number of metrics (and the bill) grows with them. An X-Ray annotation is indexed for
searching traces (filter expressions such as annotation.faculty = "science"); many distinct values cost nothing
extra per value because traces are billed per trace, and you can find individual requests but not alarm on it.
Faculty: a dimension (and an annotation) - eight values, worth graphing per faculty. Student id: never a dimension
(30,000 metrics); an annotation (to find one student's slow transcript) or a log field. Origin HTTP status: an
annotation or, better, the http.response.status field X-Ray already classifies into ok/error/fault; as a
dimension only if grouped into a few classes (2xx/4xx/5xx). Renderer name: a small set, so it could be a
dimension if renderer performance is compared over time; otherwise an annotation or metadata.

### Q5. Why tracing needed version 4
A published version freezes both code and configuration, and TracingConfig is configuration. Changing it changed
$LATEST only; version 3 kept PassThrough (I read it back: version 3 PassThrough, version 4 Active). If I had left
the alias on version 3, the console would show Active on $LATEST while every invocation through live - the one S3
triggers - ran untraced, with no error anywhere. That is Lab 10 Step 11's claim observed: the version is the unit
of deployment, so a configuration change is a deployment and needs a new version and an alias move.

### Q6. What a forced alarm proves
set-alarm-state proved the alarm exists under its name, accepts transitions, records history with a readable
reason, and that the composite follows its child. It did not prove that the threshold, statistic, period, unit and
dimensions match the published metric - that is evaluation. On this build I could prove that too: lag-high fired
on two real breaching datapoints and silence fired after three empty buckets, and both cleared from data. On real
AWS a forced test additionally proves what happens AFTER the alarm: the SNS action fires, the page arrives, the
runbook link works, the on-call person can act - which is where incidents actually fail. Testing the response even
when confident in the threshold matters because a command that appears to succeed (put-metric-alarm printing
nothing) is not evidence it did what you meant; only a transition you watched - forced, then real - is.