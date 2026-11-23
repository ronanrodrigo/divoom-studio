# Independent BluetoothController review

Reviewed 2026-11-23, static inspection of Sources/Bluetooth/BluetoothController.swift. No hardware commands sent. References to lines match the reviewed initial implementation; later edits may shift them.

## Findings

### P1 — Synchronous Bluetooth writes block the main actor and defeat cancellation/deadline

Lines 134–154 create `Task` from `@MainActor` and call `IOBluetoothRFCOMMChannel.writeSync` on that actor. `Task` does not move synchronous work to a background thread. A slow or stalled RFCOMM write prevents UI events, disconnect, delegate handling and the 60-second deadline check from running until the OS call returns. The deadline at line 144 bounds time between calls, not the call itself. This matters especially after the prior device freeze.

Use the framework's asynchronous write API, retain each Data buffer until its completion callback, and enforce a watchdog without blocking the main actor; alternatively put all transport ownership and its run loop on a dedicated worker. Cancellation should close the channel and release any pending completion/buffer once the OS no longer owns it. Test with a transport fake whose write never completes; UI/disconnect must remain responsive.

### P2 — ACK matching is opcode-level observation, not per-packet completion

Lines 127–129 reduce sent commands to a Set, and lines 214–221 record every valid response by opcode. A late response from a previous action with the same opcode can satisfy the next action after the Set is cleared. For animations every chunk uses opcode 0x49, so one response makes the aggregate appear fully acknowledged; the implementation cannot distinguish which chunks were acknowledged. This is not proof of failed transmission, but “ACK parcial N/M comandos” and “ACK de protocolo recebido” have weaker correlation than users might infer.

The protocol lacks an established transaction ID for these commands. Keep language explicitly at “resposta ao opcode observada durante envio” and never imply per-packet ACK completion. Timestamp per-action send boundaries, count/log observed responses and document that correlation is best-effort. Do not invent sequence matching for commands whose replies have not been decoded.

### P2 — Early send exits can leave busy state indefinitely

Lines 138–143 return immediately if `isOpen()` becomes false without an already-processed channelClosed callback. The task does not reset `isBusy`, status or sendTask on that path. The close callback normally handles cleanup, but delegate delay/loss or an unexpected nil connection can leave the app stuck in Enviando until the user disconnects. A generation-aware task finalizer should clear its own busy state and report interruption; it must not clear a new generation's operation.

### P3 — Exported logs truncate payloads

`hex` keeps only 160 bytes; both RX and TX logs use it. That keeps UI bounded but means exported logs cannot reconstruct image transfers for protocol investigation. If packet capture/export is desired, keep bounded binary capture files separately from display summaries and mark exports as truncated until then.

## Positive observations

- No automatic transmission on app launch, discovery or connection.
- One channel owner and generation ID prevent most stale-operation updates.
- Incoming buffer copied before the delegate callback returns, avoiding use-after-free of framework-owned bytes.
- Delegates are cleared before close; old-channel callbacks are filtered by ObjectIdentifier.
- Receiver validates framing/checksum through a length-based incremental parser, so embedded marker bytes do not terminate frames.
- Data-level ACK parser requires outer payload 04 and marker 55, and status explicitly asks the user to inspect the device.
- Transfer has no automatic retry, payload count/size limits and disconnect control.
- Connection open is asynchronous with a 15-second watchdog.

## Validation status

Codec tests: seven XCTest cases passed via SwiftPM native build system on this Mac. These cover framing/checksum/no escaping, fragmented/coalesced parser data, 2-color/256-color images, animation chunk reassembly and bounds, alarm/clock vectors. No claim of hardware compatibility follows from these tests.

Independent reference comparison additionally passed for 1, 2, 3, 5, 16 and 256-color image payloads. The comparison executed the actual `process_frame`, `process_pixels`, `convert_color`, `make_frame`, `make_framepart` methods extracted by AST from the fixed hass-divoom source (without importing its Bluetooth module or sending data). Swift output matched every byte. This specifically covers bit widths 1, 2, 3, 4 and 8 and the 256-colors-as-zero count. Scratch scripts/fixture: `work/protocol-tests/compare-reference.py`, `vectors.json`, `main.swift`.
