# AsyncLock / AsyncSignal audit

Findings from a review of every `AsyncLock` and `AsyncSignal` (from
[swift-async-stream](https://github.com/o-nnerb/swift-async-stream) 2.0.4) call site under
`Sources/RequestDL/`, focused on whether each one follows the primitives' cancellation contract:

- `AsyncLock` is cancellation transparent — acquisition is never aborted, so a cancelled task still
  takes its turn and must call `try Task.checkCancellation()` itself inside the block to bail out
  early.
- `AsyncSignal.wait()` is cancellable and throws `CancellationError`, but resolves near instantly
  once the calling task is already cancelled rather than genuinely suspending — looping over it
  with `try?` and no exit condition spins hot instead of idling.

## Fixed

- [x] **`ClientManager.client(provider:sessionConfiguration:)` never checked cancellation inside
  its `AsyncLock`.** Every request goes through this method
  (`Internals.Session.swift:38` → `Internals.ClientManager.swift`). It shares its lock with
  `cleanupIfNeeded()`, which can hold it for a while sweeping expired clients. A task cancelled
  while queued behind that sweep still took its turn, created/reused a client, and could still
  fire the HTTP request nobody wanted anymore — cancellation was never observed anywhere in
  `Tasks/` before the response arrived.
  Fixed by adding `try Task.checkCancellation()` as the first statement inside the lock
  (`Internals.ClientManager.swift:61`). Regression test:
  `InternalsClientManagerTests.manager_whenCallingTaskIsCancelledBeforeItRuns_shouldThrowCancellationError`.

- [x] **`AsyncQueue.waitUntilIdle()` / `PendingTasks.waitUntilIdle()` swallowed cancellation and
  spun.** Both did `while let signal = ... { try? await signal.wait() }`
  (`Internals.AsyncQueue.swift:70`, `Internals.PendingTasks.swift:68`). Once the calling task was
  cancelled, `signal.wait()` stopped genuinely suspending and started resolving almost
  instantly, so the `try?` turned the loop into a tight spin (lock + allocate + cancel per
  iteration) until the real work finished on its own, instead of returning.
  Fixed by checking the result of `wait()` and returning as soon as it fails. Regression tests:
  `InternalsAsyncQueueTests.asyncQueue_whenCallingTaskIsCancelled_shouldReturnWithoutJoiningCurrentEpoch`,
  `InternalsPendingTasksTests.pendingTasks_whenCallingTaskIsCancelled_shouldReturnWithoutJoiningCurrentEpoch`.
  Both were previously reachable only from test-only call sites
  (`DownloadBuffer.waitUntilIdle()`, `DataCache.waitUntilIdle()`), so the bug had no production
  impact yet — but the fix removes a latent trap for whenever that stops being true.

- [x] **`FileStreamBuffer.writeData(_:)` / `readData(length:)` didn't check cancellation inside
  their retry loops.** Both loop over short reads/writes while holding the type's `AsyncLock`
  (`Internals.FileStreamBuffer.swift:89-124`, `:133-166`), with no `Task.checkCancellation()`
  in between iterations. Backs both file uploads (`FilePayloadFactory`) and the disk cache
  (`DiskStorage`), so it wasn't purely theoretical — but each call handles one chunk at a time
  (whatever arrived from the network/stream layer), not a whole file at once, so the worst case
  was a cancelled task waiting out one chunk's worth of retries rather than the entire transfer.
  Fixed by adding `try Task.checkCancellation()` at the top of each loop iteration in both
  methods — safe since release is guaranteed by `defer` in `withLock`, matching the fixes above.
  Regression tests (new file, since `FileStreamBuffer` had no direct test coverage before):
  `InternalsFileStreamBufferTests.writeData_whenCallingTaskIsCancelledBeforeItRuns_shouldThrowCancellationError`,
  `InternalsFileStreamBufferTests.readData_whenCallingTaskIsCancelledBeforeItRuns_shouldThrowCancellationError`.

## Open — worth doing, not urgent

- [ ] **No `AsyncLock` in the project uses `Watchdog`.** All five instances
  (`Internals.Buffer.swift:71`, `Internals.FileStreamBuffer.swift:48`,
  `Internals.Client.swift:33`, `Internals.ClientManager.swift:28`,
  `Internals.EventLoopGroupManager.swift:19`) are created with the plain `AsyncLock()`
  initializer. `Watchdog` is opt-in and free when `nil`, so this isn't a bug — but it means a
  critical section that starts hanging (deadlock, future bug) would surface only as "requests
  stop making progress," with no log or signal pointing at the lock. Worth wiring up at least on
  `Internals.Client` and `Internals.ClientManager` — both sit on every request's path — in debug
  or test builds via `Issue.record`.

## Not audited

- `Tests/RequestDLTests/.../LocalServer.swift:32` also holds an `AsyncLock`. It's test
  infrastructure, not shipped in the library, so it was left out of this pass — flag separately
  if it ever needs a look.
