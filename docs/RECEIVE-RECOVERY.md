# Receive recovery and connection safeguards

**0.1.0-alpha.11** adds bounded receive recovery and stronger connection-state handling. Automated tests cover these changes; live listening and extended operation remain pending. Installing a new release is a stopped upgrade, not an automatic update to a running bridge.

## Following overs

A validated next-over header can wait while the previous over finishes playout. Only one following over is retained, and both overs share the existing **four-frame receive queue limit**. The original over drains first; the following over starts its own native receive metadata and normal 100 ms cadence. Excess traffic remains explicitly rejected rather than creating an unlimited backlog.

## Native room proof

The observer publishes complete snapshots through a same-directory replacement coordinated with the adapter by a path-specific Windows mutex. The lock covers only the small file transaction, never the native-window read. Reads use shared access, bounded contention waits and at most two retries. A missing, stale, untrusted or persistently unavailable proof still closes forwarding.

Successful native observations carry a per-observer connection-generation token. Continuity requires overlapping complete log lines with compatible absolute line counts. An explicit connection event, disconnect, log reset, lost overlap or restarted observer changes or invalidates the token. Reconnecting to the same room within the same timestamp second therefore cannot preserve an old receive context.

A process-bound native-log read failure closes forwarding and discards all queued audio. For up to **three seconds**, the engine may retain only the previous validated caller, gateway and expected packet sequence. Recovery requires a fresh, successful proof with the identical connection token, all other forwarding gates open, and matching incoming source/gateway traffic no more than 32 positions ahead of the expected sequence. Larger advances must also be consistent with elapsed time. An observed header, terminator or end flag while blocked invalidates the retained context.

Explicit Stop, a room/connection change, native process mismatch, stale/untrusted proof, a node-room barrier, transport failure, disabled forwarding or an intervening native over clears the old context. No old queued audio is replayed after a pause. Protocol DLL, adapter and observer changes must be selected together with the matching artifact manifest.

## Gaps, sequence jumps and pressure

- The existing 400 ms receive idle cutoff releases playout and clears queued audio.
- Within one second of the last valid ingress, matching traffic may resume from a retained, validated header context. This is limited to ten positions ahead of the expected sequence and constrained by elapsed time.
- Backward, duplicate, excessively large and implausibly fast sequence jumps remain rejected. Modulo-128 wrap is supported.
- Valid frames dropped because the four-frame queue is full advance the ingress sequence, but never enter playout. A known local drop must not cause the remainder of the over to be rejected as a new sequence error.
- Recovery emits only encoded voice carried by newly admitted real packets. There is no silence generation, audio repetition or catch-up burst.

## Verification

`build.ps1` includes receive-boundary, recovery, safety/stress, proof-continuity, actual PowerShell dispatch, observer-state and concurrent proof-publication tests. Native-window input and hardware actions are isolated or injected; these are not listening tests.

The healthy-traffic trace covers measured/unmeasured receive modes and both directions, including complete serial/network output and timestamps. The alpha.11 protocol matched the alpha.10 reference trace byte-for-byte, including timing. This is a regression check, not a claim of universal receiver compatibility or live audio acceptance.
