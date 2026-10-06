# URLSession-only CI: a refused connection takes ~10 minutes to fail despite `Timeout(.seconds(3), for: .resource)`

> Local note, not for the repository. Written as an issue so it can be pasted into GitHub later if wanted.
> Everything below comes from CI logs and local runs I made; what is a guess is marked as one.

## Summary

In the `🌐 URLSession-only Build & Test` job, `aRequestThatNeverGetsSent_isReportedAsStartedThenFailed(_:)` (executor `urlSession`) takes about **10 minutes** to fail, and then fails with `Condition still unmet after 120.0s`. The request it makes has a 3 second resource budget. It is red on `main` and on every PR I looked at, so that job is red most of the time and hides other failures.

The test is `Tests/RequestDLTests/Tasks/Sources/Modifiers/Monitor/RequestMonitorTests.swift` (from #381):

```swift
await #expect(throws: (any Error).self) {
    _ = try await DataTask {
        BaseURL(.http, host: "127.0.0.1:1")   // nothing listens here
        Path("/resource")
        executor.session
        Timeout(.seconds(3), for: .resource)
    }
    .monitor(monitor)
    .result()
}

try await eventually(timeout: 120) { monitor.hasEnded }
```

The test lasts 570–620 s in total. The `eventually` is bounded at 120 s, so the `.result()` call above it alone took roughly 450–500 s to throw, against a 3 s budget.

## Evidence

All in the `🌐 URLSession-only Build & Test` job, case `executor → urlSession`, `Condition still unmet after 120.0s`:

| Where | Head | Run / job | Test duration |
|---|---|---|---|
| `main` (squash of #380) | `3aa918d8` | 37215330232 / 111474554602 | 611.9 s |
| #380, first attempt | `96407dd8` | 37208101924 / 111453602108 | 619.2 s |
| #386 (tests only, no source change) | `a41720e2` | 37218134043 / 111482766369 | 588.6 s |
| #385 (my own copy of the pattern, since removed for `urlSession`) | `13ea0ae3` | 37218131747 / 111482805871 | 585.9 s |
| #385 | `58694c83` | 37315837929 / 111782232541 | 573.8 s |

Passed, for comparison:

- #380, after rerunning the failed jobs (same code, attempt 2).
- `main` at `b03a18a8`, the commit that introduced the test (run 37119408999): only `visionOS` was red there.
- The `macOS` job (default traits) runs the same test for the `urlSession` executor and normally passes.
- Locally (macOS, arm64), in **both** modes: the whole monitor suite passes in ~25–60 s, and the refused-connection cases take about 3 s each. I could not reproduce the delay.

#386 changes no source, so the failure does not come from the metrics work: it was already there on `main`.

## What it might be (guesses, none verified)

1. **The resource timeout does not fire** for the `URLSession` executor on that runner while the connection is being established. `runExchange` awaits `session.bytes(for:delegate:)`, and before it returns `box.task` is not set, so cancellation relies on `URLSession`'s own async cancellation handling (there is a comment on this in `Internals.URLSessionClient.executeSessionTask`). If that does not abort a connect in progress on that macOS version, the budget is not honoured.
2. **`127.0.0.1:1` behaves differently on that runner**: if the SYN is dropped instead of answered with a reset, `URLSession` waits for its own timeouts (the default request timeout is 60 s), possibly more than once.
3. **Runner saturation.** The test's own comment says the budget "has been seen to take over a minute to fire" on a saturated runner. But 570–620 s is an order of magnitude beyond a minute, and the NIO executors, on the same job and in the same suite, do not show it.

Why only this job: the URLSession-only job runs the suite without NIO. I did not find what in that configuration would matter; it may just be the runner.

## Same family, seen in other jobs

Cancellation and resource-deadline timing under `URLSession`, on CI runners, failing in other places:

- `dataTask_whenResourceTimeoutFiresMidFlightUnderRequiredURLSession_cancelsTheUnderlyingURLSessionTaskAndThrows()`: `Expectation failed: !(stillRunning)` (`RawTaskExecutorDispatchTests.swift:475`), on the `iPadOS` job (#380, #386).
- `sessionTask_whenCancelledMidDownload_stopsRunningSoonAfter()`: `Expectation failed: !(stillRunning)` (`InternalsURLSessionClientSessionTaskTests.swift:258`), on the `iOS` job (`main` at `3aa918d8`, #385).
- `dataTask_whenAPreFlightStepStallsPastTheResourceTimeout_throwsInsteadOfWaitingItOut()`: `elapsed` 18.4 s (on `main`) and 34.9 s (#380, `iPadOS`) against a 15 s limit.
- `race_whenOperationFinishesBeforeDeadline_neverCancelsGivenSeed()`: failed after 16 s on the URLSession-only job (#380).

`InternalsResourceDeadlineTests` already documents stalls of 35–64 s of a 10 ms operation on simulator runners. I have not established whether these are all runner contention or whether some of them are one real bug in how a `URLSession` task is cancelled.

## How I would look at it

1. Make the test report how long `.result()` took (not only whether it threw), so a CI log says directly whether the budget fired late or never.
2. Run only this test on CI, repeatedly, in the URLSession-only configuration (a throwaway branch, or `workflow_dispatch` if the workflow allows it), with timestamps around `session.bytes(for:delegate:)` and around the cancel that `Timeout(.resource)` triggers.
3. Try the same request against a port that answers with a reset, and one that drops: if only the dropped one is slow, it is guess 2.
4. If the cancel reaches `URLSession` and the task still does not end, that is a bug in the `URLSession` executor and not in the test.

## Impact

- The URLSession-only job is red on `main` and on every PR, and takes about 11–12 minutes instead of about 3, with the test alone using ~10.
- It hides other failures in the same job (a second real failure would be read as "the usual one").
- Each of my PRs (#385, #386, #387) had to be explained as "red because of `main`".

## What I did about it

In #385 I had added a test of the same shape (a request to the closed port, to check that a `RequestMonitor` still hears about a transaction with no response). It failed the same way, so I excluded the `urlSession` executor from it. I did **not** touch the original test: skipping `urlSession` there would hide a possible real problem.

## Not verified

- Whether the budget fires late or never.
- Why only the URLSession-only job, and why it passes on `main` at `b03a18a8`.
- Whether the tests in "Same family" share this cause.

---

# Second note: Linux, `HTTPClientError.cancelled` in ordinary NIO requests against the local server

> Same status as above: from CI logs and from runs I made in an Apple `container` (`swift:6.2`, 4 CPUs).
> Guesses are marked as such. This one is a separate problem from the URLSession one.

## Summary

On Linux, a request that has nothing wrong with it, made with the NIO executor against the `LocalServer` of the tests, now and then ends with `HTTPClientError.cancelled`. Which test it hits changes from run to run, and it passes when the same test runs alone. `main` shows it with none of my changes.

## Evidence

**GitHub CI, `🔧 Linux` job:**

| Where | Head | Run / job | Test |
|---|---|---|---|
| #385, second run | `58694c83` | 37315837929 / 111798841204 | `dataTask_whenClientCertificateChainHasIntermediateUnderNIORequired_completesHandshake()`, `DataTaskTests+NIO.swift:198`, after 7.7 s. 1950 tests, 1 issue. |

In the other Linux CI runs I looked at (#380, the first run of #385, #386 and #387) the job passed.

**My container, `main` alone at `a4c25b48`, async-http-client 1.39.0 (resolved on its own), memory sampled, never below 4 GB free:**

| Run | Result |
|---|---|
| first valid run | 1815 tests, 2 issues: `dataTask()` and `dataTask_whenCAEnabled()`, both `HTTPClientError.cancelled` |
| multi-run 1 | 1 issue: `dataTask_whenRedirectStrategyDoesNotFollowOverNIO_returnsRedirectResponseUnfollowed()`, `HTTPClientError.cancelled` |
| multi-run 2, 3 | clean |

That is 2 of 4 runs red, with different tests each time.

**My container, the branch of #380, 12 GB:** 1 of 4 runs red, `insecureFlagReachesASelfSignedLocalServer()` (`CURLTaskTests.swift:132`), `HTTPClientError.cancelled`. At 10 GB, a run with `dataTask_whenCAEnabled()` and `dataTask_whenRedirectStrategyDoesNotFollowOverURLSession_returnsRedirectResponseUnfollowed()` failing the same way, and `session_whenUploadingFile_shouldBeValid()` receiving 200 MB where 100 MB was expected (it looked like the upload was sent twice).

**In isolation:** the three failing tests of that 10 GB run passed when I ran only them (9 of 9 tests).

## What stays the same across the cases

- Always `HTTPClientError.cancelled`, from an ordinary request to the local TLS server, on the NIO executor.
- It only appears in a full-suite run, with the tests in parallel; it did not appear in isolation.
- Different test every time, in `DataTaskTests`, `CURLTaskTests` and `RedirectStrategyDataTaskTests`.
- Memory does not explain it: the runs where it appeared had at least 4 GB free.
- It does not come from the metrics work: `main` alone at `a4c25b48` has it, and that commit does not have the metrics, and the #385 test that failed has no `RequestMonitor` attached.

## Guesses, none verified

1. **A shared pooled client gets shut down while another test is using it.** The tests share the dedicated `Session.localServer` pool, and `Internals.ClientManager` has an idle-cleanup sweep and a ceiling eviction. If either closes or replaces a client that another concurrent test already got, that test's request would be cancelled. `isRunning` is meant to prevent exactly this, so if it happens it is a hole in how a client is counted as busy.
2. **Port reuse between tests.** Several tests bind the same fixed `LocalServer` ports (8888, 8887, 8896). Another session's tests on the same machine showed `Address already in use` on macOS; I have no sign of it in these Linux runs.
3. **A change in async-http-client 1.39.x.** `main` resolves the fork on its own (`from: "1.38.2"`), so all my `main` runs used 1.39.0. I never ran `main` with 1.38.2 pinned, so I cannot tell whether the failures started with the fork update.

## How I would look at it

1. Pin the fork to 1.38.2 on a throwaway branch and run the full Linux suite several times in the same container. If it goes away, it is the fork.
2. Find who produces `HTTPClientError.cancelled` for these requests (a task cancellation by the test, a client shutdown, or the request bag), by logging at the point where the client is closed or replaced in `Internals.ClientManager` and comparing with the time of the failures.
3. Give each of those tests a session of its own instead of the shared `Session.localServer`, and see whether the failures stop. If they do, it is guess 1.

## Impact

- The Linux job goes red now and then on PRs that have nothing to do with it, and each time it costs a rerun and an explanation.
- The upload that arrived doubled suggests that, in at least one case, a cancelled request was retried, which would make this more than a test problem. That is the weakest part of the evidence: I saw it once.

## Not verified

- Whether it is the fork, the pooled client, or something in the tests.
- Whether the doubled upload and the `cancelled` are the same cause.
- Whether macOS has it. I never saw it there.
