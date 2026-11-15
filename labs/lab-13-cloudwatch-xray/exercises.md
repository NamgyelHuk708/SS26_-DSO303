# Lab 13 exercises and your-turn answers

## Step 8 your turn - a pattern for the ERROR line only
Tested with test-metric-filter against the four Step 7 messages and one false positive
(USMS_EVENT {"event":"transcript.processed","reason":"no ERROR here"}):
- ERROR               -> matches message 4 only; the false-positive line ALSO matches (1). Term matching is by
                         token, so any line that merely mentions ERROR is counted as a failure.
- "ERROR USMS_EVENT"  -> matches message 4 only; the false positive does NOT match (0). A quoted phrase requires
                         the exact sequence, i.e. a line that STARTS a failure event.
Production: I would not accept plain ERROR. A free-text field (a reason, a student's comment) containing the word
would inflate CentralErrorCount and could fire an alarm with nothing wrong. The quoted phrase ties the metric to the
log format (an interface, as Step 7 says): if the marker changes, the metric silently drops to zero - so the
format must be documented and tested, which is what test-metric-filter is for.

## Step 10 your turn - what defaultValue does
NotifyCount over 13:34-13:49 (before any upload): Datapoints [] (EMPTY). Over 14:09-14:19 (with the upload):
Sum 2, SampleCount 4. An EMPTY list means no log event reached the group in that window, so the filter emitted
nothing - not even its default. A list of zeroes would mean events arrived but none matched: defaultValue is
emitted per NON-matching event (here the 2 "usms-transcript-notifier: 1 record(s)" lines gave the 2 extra samples),
not per empty period. My build produced the empty list - so silence stays silence, which is why the silence alarm
(Step 19) must treat missing data as breaching.

## Step 13 your turn - rollback through the alias
live -> 1: the payload had no trace_id (keys, processed); live -> 3: trace_id and seconds again. Same alias ARN,
two payload shapes; versions $LATEST, 1, 2, 3 throughout; the bucket notification untouched. A real rollback of this
deployment is one update-alias call - effective for the next invocation, seconds in total. Lab 10's Lambda@Edge
rollback is much slower: CloudFront names a numbered version (no aliases at the edge), so rolling back means updating
the distribution's association and waiting for the change to deploy to every edge location (minutes), and old
replicas can keep serving the previous version meanwhile.
