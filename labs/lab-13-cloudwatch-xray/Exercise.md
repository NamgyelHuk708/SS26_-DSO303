# Lab 13 Independent Exercises

> Status: the three your-turn answers and Exercise 4 are complete. Exercises 1, 2, 3 and 5 list the approach and the commands; their **Result** sections are filled in from the output of each run.

---

## Your-turn answers from the main lab

### Step 8 – a pattern for the ERROR line only

Tested with `test-metric-filter` against the four Step 7 messages and a false positive (`USMS_EVENT {"event":"transcript.processed","reason":"no ERROR here"}`):

| Pattern | The four Step 7 lines | The false-positive line |
|---|---|---|
| `ERROR` | matches message 4 only | **matches (1)** |
| `"ERROR USMS_EVENT"` | matches message 4 only | does not match (0) |

![Step 8](LAB_13(image)/8.png)

Term matching is by token, so plain `ERROR` counts any line that merely mentions the word. I would not accept it in production: a free-text field (a reason, a student's comment) containing "ERROR" would inflate `CentralErrorCount` and could fire an alarm with nothing wrong. The quoted phrase counts only lines that start a failure event – at the cost of tying the metric to the log format, which must therefore be documented and tested. I deployed the lab's `ERROR` (the dashboard and Exercise 1 assume it) and record this as the production change.

### Step 10 – what `defaultValue` does

| Window | `NotifyCount` |
|---|---|
| 13:34–13:49 (before any upload) | `[]` – empty |
| 14:09–14:19 (with the upload) | Sum 2, SampleCount 4 |

![Step 10](LAB_13(image)/10.2.png)

An **empty** list means no log event reached the group in that window, so the filter emitted nothing – not even its default. A list of zeroes would mean events arrived and none matched: `defaultValue` is emitted per **non-matching event** (the two `usms-transcript-notifier: 1 record(s)` lines gave the two extra samples), not per empty period. My build produced the empty list, so silence stays silence – which is why the silence alarm must treat missing data as breaching.

### Step 13 – rollback through the alias

| Alias | Payload keys | `trace_id` |
|---|---|---|
| `live → 1` | `keys, processed` | absent |
| `live → 3` | `keys, processed, seconds, trace_id` | present |

![Step 13](LAB_13(image)/13.2.png)

The same alias ARN returned two payload shapes; versions `$LATEST, 1, 2, 3` stayed throughout and the bucket notification was never touched. A real rollback of this deployment is one `update-alias` call, effective for the next invocation – seconds. Lab 10's Lambda@Edge rollback is far slower: CloudFront names a numbered version (no aliases at the edge), so a rollback means changing the distribution's association and waiting for it to deploy to every edge location, minutes during which old replicas may keep serving.

---

## Exercise 1: Extract a value instead of counting events

**Requirement:** a third filter, `usms-transcript-seconds`, on `/usms/central/application`, publishing `TranscriptSecondsFromLogs` from the `seconds` field rather than a constant.

**The obstacle:** `USMS_EVENT {...}` is not pure JSON, so the JSON dialect (`$.seconds`) cannot read it. Two options, tested first with `test-metric-filter`:

| Option | Pattern | metricValue | Cost |
|---|---|---|---|
| A – pure JSON lines, marker as a field | `{ $.marker = "USMS_EVENT" && $.seconds >= 0 }` | `$.seconds` | the line format changes; the path-B parser and anything splitting on `USMS_EVENT {` must change |
| B – keep the prefix, seconds as its own token | `[marker="USMS_EVENT", secs, payload]` | `$secs` | the value appears twice in the line, and its position becomes an interface |

**Commands:** the three `test-metric-filter` calls (sent in chat), then the emitter change for the chosen option, then:

```bash
aws logs put-metric-filter --log-group-name /usms/central/application --filter-name usms-transcript-seconds \
  --filter-pattern '<chosen pattern>' \
  --metric-transformations metricName=TranscriptSecondsFromLogs,metricNamespace=USMS/Application,metricValue='<$.seconds or $secs>'
./scripts/utilities/usms-emit-telemetry.sh science 0.77
./scripts/utilities/usms-emit-telemetry.sh engineering 2.65
# read back TranscriptSecondsFromLogs: Maximum 2.65, Minimum 0.77, SampleCount 2
```

**Result:** *to fill in from the run (ex1.1.png, ex1.2.png).*

**Two routes to one measurement:** `TranscriptLagSeconds` is published by the code that measured it; `TranscriptSecondsFromLogs` is derived from what the code wrote down. *Which I would keep, and why: to fill in after the run.*

---

## Exercise 2: Make the dashboard portable and add a widget

**Requirement:** generate `templates/lab-13-dashboard.json` from `USMS_ACCOUNT_ID` and `AWS_REGION_COURSE`; add a sixth widget (`CentralErrorCount`, last three hours, threshold annotated); re-put; update `verify-lab-13.sh` from 5 to 6 widgets.

**Approach:** a small generator script (an unquoted heredoc, so the file holds values, not commands); the sixth widget at `y=12`, below the existing rows. The first metric widget should also gain **`Faculty=evidence`** – the faculty the notifier itself publishes, which the lab's dashboard leaves out.

**Result:** *to fill in (ex2.1.png, ex2.2.png): DashboardValidationMessages `[]`, 6 widgets, no overlap, no literal account id, verify back to FAIL=0.*

**On the hard-coded widget count:** *to fill in.*

---

## Exercise 3: Are these thresholds defensible?

**Requirement:** `scripts/utilities/usms-threshold-report.sh` – one JSON document per `usms-` alarm with its configuration, the observed min/avg/max/samples of its metric over 24 hours and `threshold_ever_breached`; composite alarms handled with nulls; JSON only on stdout; works from any directory and under `set -u`.

**Expectation from what I already observed:** lag-high's threshold **was** breached (4.20 s and 3.70 s); `usms-enrolment-queue-high` (Lab 6) is the likely "never approached" finding.

**Result:** *to fill in (ex3.1.png).*

---

## Exercise 4: Design the USMS observability plan

Written in full in [`notes/lab-13-observability-plan.md`](../../notes/lab-13-observability-plan.md): the right layer for each of the registrar's four complaints, a log group taxonomy with an audit group, three SLIs, every alarm with its missing-data policy, a cost estimate with cardinality, and the one thing not to build yet.

---

## Exercise 5: Leave an alarm the next alerting lab can attach to

**Requirement:** `outputs/lab-13-alarm-actions-draft.json` (three alarms, urgency, placeholder SNS ARNs built from the real account id), validated but **not applied**; at least five emitter runs and `outputs/lab-13-latency-baseline.json`; a generated, git-ignored `outputs/lab-13-alerting-readiness.txt`; `AlarmActions` still `[]`; verify still 49/0.

**Data already in hand:** emitter latencies 0.51, 2.40, 3.10, 4.20, 3.70 s; lag-high fired and recovered on data; silence fired after 15 minutes and recovered.

**Result:** *to fill in (ex5.1.png, ex5.2.png).*

---

## Summary

| Exercise | Status |
|---|---|
| Your-turn answers (Steps 8, 10, 13) | complete |
| 1 – extracted value | to run |
| 2 – portable dashboard | to run |
| 3 – threshold report | to run |
| 4 – observability plan | complete (`notes/lab-13-observability-plan.md`) |
| 5 – alerting hand-off | to run |