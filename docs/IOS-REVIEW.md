# Independent iOS review

Reviewed 2026-11-23. Scope: `Sources/iOS/Bluetooth`, `Sources/iOS/App`, iOS lifecycle, Mobile-Info.plist and the iOS target in project.yml. Read-only source review; no simulator, build, signing change, scan, connection or device command was executed. Line references are from the reviewed version and may move after fixes.

## P1 — Same-device reconnect accepts callbacks from an old connection attempt

`Sources/iOS/Bluetooth/MobileBluetoothController.swift:448-465`, `:468-480`, `:506-520` identify callbacks only by the peripheral UUID (and, for writes, characteristic UUID). The generation ID protects Tasks and timeouts but is not bound to delegate events. `resetConnection` at `:183-187` calls asynchronous `cancelPeripheralConnection`, then immediately discards the peripheral and enables the Connect action. Reconnecting the same Ditoo reuses its UUID and may reuse the CBPeripheral instance.

Sequence: disconnect/cancel A, begin attempt B to the same device before the old disconnect callback is delivered, receive A's `didDisconnectPeripheral`, and the UUID guard matches B. It resets B, cancels its continuation and reports a disconnection for the new attempt. An already-enqueued old didWrite notification can likewise match a new pendingWrite and resume the wrong continuation. The extra Task hop in each callback increases the window.

**Fix:** serialize reconnect behind the actual completion of cancellation, keep a disconnecting state that disables Connect until the old attempt is closed, and bind queued peripheral delegate deliveries to an attempt/delegate epoch captured when the delivery is received. Check the characteristic/service object against the current discovered objects where possible. Do not solve this only with the same peripheral UUID or object identity: CoreBluetooth can reuse the same peripheral object. Add a fake event-sequence test for connect A → cancel A → request B → late disconnect/write A; B must not be reset or acknowledged by A's events. No physical test is needed to reproduce the state machine issue.

## P2 — CoreBluetooth resetting preserves a stale connected session

`MobileBluetoothController.swift:424-430` deliberately skips `resetConnection` for `.resetting`, while leaving `isConnected`, `notificationsReady`, profile and characteristic references unchanged. If a reset interrupts a connected session and `.poweredOn` follows, `beginScanIfReady()` is a no-op because wantsScan is false. The app can remain marked connected and send-enabled using stale session objects; Connect/Scan are blocked by isConnected.

**Fix:** treat a transition away from poweredOn during an active session as session invalidation: cancel pending transfer/continuations, clear connected/profile state, stop the scan, and require a new explicit user connection. Returning to poweredOn must not auto-connect or auto-send. Add a fake poweredOn → connected → resetting → poweredOn sequence test.

## P2 — Imported JSON size limit is checked after unbounded main-thread read

`Sources/iOS/App/MobileAppModel.swift:141` loads the complete selected file with `Data(contentsOf:)` before checking the 2 MB limit. A very large user-selected JSON can allocate far above the intended limit and stall the iPhone UI or cause memory termination before validation.

**Fix:** inspect file size before loading and perform a bounded read of at most limit+1 bytes; reject excess before decoding. File metadata alone can race, so the read itself needs the bound. Existing validated() checks correctly protect empty projects, frame RGB length, duplicate IDs and duration; retain them. Add a large/sparse fixture test that confirms early rejection without loading its full data.

## Non-blocking limitations and checks

- BLEProfile.rcspEnvelope's length/checksum matches the pinned Plus reference: command+body is wrapped once, not a full Classic frame. Packet ACK parser requires `04 33 55` plus four bytes and the send loop compares the complete UInt32 packet number. Reply framing/checksum is validated by the shared parser. No framing arithmetic error found.
- The Plus one-color adaptation drops the redundant 32-byte index plane while preserving the three RGB bytes. Multi-color payloads are unchanged. Animation frames are concatenated palette frames, with per-frame duration and bounded 48 KB total; MiniToo Zstandard data is not used.
- Animation upload waits for the announce packet ACK and the separate readiness response before sending data chunks. One packet is in flight at a time; no automatic retry.
- Cancellation resets the continuations and queued Tasks; timeout paths clear busy. Strict async writes avoid blocking the main actor. No double-resume path was found within a single uninterrupted generation; the cross-generation callback race above remains the blocker.
- Controller init does not create a manager, scan, connect, restore or send. Only the explicit Scan action creates CBCentralManager. This respects AGENTS.md's no automatic Bluetooth activity invariant.
- Lifecycle `DivoomMobileApp.swift:11-17` calls becameInactive/enteredBackground; `MobileAppModel.swift:88-90` stops continuous dashboard scheduling and editor playback. It does not resume automatically in active. `bluetooth-central` does not grant a permanent custom clock/polling loop; the current foreground-only promise is accurate.
- A currently in-flight one-shot upload is allowed to finish when the continuous dashboard scheduler is stopped. The inactive message should say scheduling is paused rather than implying every byte already stopped. This is a wording/scope choice, not an observed background scheduling failure.
- State restoration and iOS26 Live Activity support are absent. Do not market persistent background transmission or reconnection until implemented and physically validated. The app may keep the last image or a device-native loop; it cannot independently update rendered time/weather while suspended.
- iOS target uses CoreBluetooth and an iOS17 minimum, automatic Apple Development signing and the required Bluetooth privacy string. No private RFCOMM API or MFi requirement was introduced. Actual team/provisioning and real-iPhone installation remain separate from simulator/UI validation.
- User-facing alarm state is explicitly the configuration saved on the iPhone, with no readback guarantee. No false claim of confirmed device scheduling found in the inspected UI.

## Verdict

Address the P1 connection-attempt race and the P2 resetting-state recovery before claiming reliable reconnection/transfer. Keep automated byte-vector/state-machine checks distinct from real Ditoo/iPhone validation. This review does not establish physical Bluetooth compatibility or visible rendering.

## Resolution review — 2026-11-23

The fixes were independently reread in the current sources. The original findings above are retained as history; the three findings are now **resolved by source inspection**, subject to normal runtime/hardware validation.

- **P1 resolved:** `MobileBluetoothController.swift:143-157` gates connection attempts and creates an immutable `EpochPeripheralDelegate` per session. Events reach `receivePeripheralEvent` at `:451-452`, which checks both epoch and device through `BLESessionGate.accepts`. Reset invalidates the epoch before resuming old continuations. Cancelling a live attempt establishes the cancellation barrier (`:178-185`); `terminalConnectionEvent` releases it and retires the central manager (`:497-510`). New discovery requires a fresh explicit user action. Central callbacks retain and verify the originating manager identity across the MainActor hop (`:528-584`), preventing already-queued old-manager events from affecting its replacement. `Tests/iOS/BLEProfileTests.swift:94-125` now covers barrier/epoch rejection and stack reset in the pure gate. These tests are present and were inspected; this reviewer did not execute them.
- **P2 resetting resolved:** `MobileBluetoothController.swift:527-543` handles resetting with the other non-poweredOn states (apart from initial unknown): stops scanning, calls resetConnection, clears continuations/profile/characteristics, and discards the manager. The app remains disconnected until the user initiates a new search; no automatic reconnect or send was introduced.
- **P2 bounded JSON resolved:** `PixelProject.swift:17-28` requires a regular file with metadata size within 2 MB and independently limits `FileHandle.read(upToCount:)` to limit+1 bytes before decoding/validation. The handle is closed with defer. Both mobile and desktop models call this shared loader. `Tests/PixelMediaTests.swift:126-137` includes a valid project and a 100 MB sparse oversized fixture. This removes the original unbounded allocation path even if a file grows after the metadata check.

No remaining blocker was identified in the reviewed correction delta. The reviewer did not run builds, tests, simulators, scans or device commands. Build/test results and iPhone installation reported by the coordinating agent are separate evidence. Successful signing/installation and these source fixes do not establish visible Ditoo behavior, actual reconnect reliability, background throughput or firmware compatibility; those remain physical acceptance checks.

## Revisão de reconexão automática — build 6

O pedido posterior do usuário autorizou conexão automática, sem comandos de tela. As observações anteriores sobre ausência de restauração descrevem a versão inicial e não o build 6. Agora o lifecycle em App.init chama startAutomaticConnection, que só cria o manager com preferência ativa e alvo válido. O construtor do controller permanece sem efeitos Bluetooth.

A revisão independente examinou persistência, seleção exclusiva do alvo salvo, protocolo estável, cancelamento/desconexão manual, esquecimento, espera progressiva, retorno do Bluetooth e restauração. O achado de conclusão prematura antes da assinatura de notificações foi corrigido: no caminho automático, busy e o timeout de descoberta permanecem até notificações válidas. Não foram identificados bloqueadores restantes no delta. A revisão estática não comprova reconexão física nem comportamento em segundo plano.
