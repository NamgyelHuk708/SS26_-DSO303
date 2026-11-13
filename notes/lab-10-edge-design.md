# Transcript delivery – edge design (Lab 10, Exercise 4)

**Requirements from the registrar:** (R1) no transcript without a valid session token, and the check must not cost an origin request; (R2) a corrected transcript must stop being served within five minutes, without paying to re-fetch unchanged transcripts every five minutes; (R3) a report of refused requests by faculty for the Dean's office; (R4) survive one edge location being unable to reach the origin.

## 1. Where each piece of logic runs

| Logic | Where | Why |
|---|---|---|
| Lowercase the URI | **CloudFront Function**, viewer-request | Pure string work on every request. CloudFront Functions run in sub-millisecond time at every edge location and cost a fraction of Lambda@Edge – the right tool for something this small and this frequent. |
| Check the session token (R1) | **CloudFront Function**, viewer-request, if the token is an HMAC-signed value (the `cloudfront-js-2.0` runtime includes a `crypto` module with HMAC); **Lambda@Edge viewer-request** if it must verify an RS256/JWKS-signed JWT or call anything over the network | Either way it runs *before* the cache, so a refused request costs one edge execution and no origin request – that is R1's cost condition. Lab 10's `usms-edge-viewer-request` proved the shape: a missing header returns 403 and the chain stops at one stage. I would start with the CloudFront Function and only move to Lambda@Edge if the token format forces it. |
| Security headers | **A CloudFront response headers policy** (no code), or Lambda@Edge **origin-response** as in Lab 10 | A managed response headers policy sets HSTS, X-Content-Type-Options, X-Frame-Options, Referrer-Policy and CSP declaratively. If code is needed, origin-response is the right trigger: it runs once per cache miss and the headers are cached with the object, whereas viewer-response would run on every hit for the same output (Step 12). |
| Invalidate a corrected transcript (R2) | **Regional Lambda**, triggered by the S3 upload | Nobody is waiting for it, it needs to call the CloudFront API, and it belongs next to the data – the same reasoning as `usms-transcript-notifier`. |
| Count refusals by faculty (R3) | **Regional analytics** over CloudFront logs (see 4) | Not on the request path at all. |

## 2. The cache key

**In the key:** the normalised URI only. A transcript URI already contains the student ID (`/transcripts/2026/stu-00417.json`), so one object maps to one cache entry.

**Deliberately not in the key:** the session token, `Authorization`, cookies and the query string. Every extra key element multiplies the stored copies of each object and lowers the hit rate; with the token in the key, every login would create a new cache entry for the same unchanged file. The token is *checked* at viewer-request and then dropped from the key – checking and caching are separate decisions. (Lab 10's configuration forwarded `x-usms-student`; for production I would keep it as a checked header but not a cache-key header.)

## 3. Five-minute corrections without re-fetching unchanged transcripts (R2)

Two approaches meet both halves; I would use the first and keep the second as the safety net:

- **Long edge TTL + targeted invalidation.** Cache transcripts at the edge for a long time (for example `s-maxage=86400`). When the registrar uploads a correction, the S3 `ObjectCreated` event triggers a regional Lambda that calls `CreateInvalidation` for exactly that path. Unchanged transcripts are never re-fetched; a corrected one is gone from every edge within minutes. Invalidation paths are free up to a monthly allowance and then charged per path (to verify on the CloudFront pricing page before committing), which is cheap for a few corrections a day.
- **Short TTL + revalidation.** Keep `max-age=300` as Lab 10 set it, but let the edge revalidate with the object's ETag: an unchanged transcript costs a conditional `GET` answered with `304 Not Modified` and no body. This meets "within five minutes" with no extra code, but still costs one small origin request per object per five minutes.

Note on the two headers Lab 10 set: `max-age` controls the **browser's** cache and `s-maxage` the **edge's**. With invalidation driving freshness at the edge, the browser TTL must stay short (`max-age=300`), because an invalidation cannot reach a browser.

## 4. Where the refusal report comes from (R3)

Edge function logs land in CloudWatch Logs **in the region nearest the viewer** (as `/aws/lambda/us-east-1.<function>`), so they are scattered across regions and are the wrong source for a report. Instead: enable **CloudFront standard logs** (or real-time logs to Kinesis) into one bucket – every request, with its status code and edge location – and query them with **Athena** for `status = 403` under `/transcripts/`, grouping by the faculty encoded in the student ID or looked up from a student table. The viewer-request function can add the reason to its 403 (as Lab 10's `x-usms-edge: viewer-request-deny` does) so refusals are distinguishable from other 403s.

## 5. The requirement an edge function is the wrong tool for (R4)

"Survive one edge location being unable to reach the origin" is an **availability** requirement, not request logic. An edge function cannot make an unreachable origin reachable. The right tool is a **CloudFront origin group with origin failover**: a primary origin (`usms-student-data`) and a secondary (a replica bucket in another region via S3 Cross-Region Replication), with failover on 5xx/timeouts. Combined with long edge TTLs from 3, an edge that already holds a transcript keeps serving it even while the origin is unreachable. (R3 is also not edge work – it is analytics.)

## What I would measure first

The **cache hit ratio** and the **number of corrections per day**. If corrections are rare (a handful a day), invalidation is clearly cheaper than revalidating every transcript every five minutes; if they become frequent (hundreds a day across many paths), the invalidation charges and the risk of missed events grow, and I would switch to the short-TTL revalidation approach. I would also measure the **share of 403s** at viewer-request: if it is large, moving the token check to a CloudFront Function matters a lot for cost; if it is tiny, Lambda@Edge's flexibility costs little.

## Things to verify before implementing

The exact token format (decides CloudFront Function vs Lambda@Edge); current invalidation and CloudFront Functions pricing; and that a response headers policy supports every header the security team wants (otherwise keep the origin-response function).
