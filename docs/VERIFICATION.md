# Compatibility and testing

**WiresX 2 YSF Bridge 0.1.0-alpha.13** remains an experimental alpha. This release focuses on setup, status and interrupted-session recovery while retaining the established alpha.10 voice/protocol and YSF-link runtime. Alpha.11/12's experimental receive-recovery implementation is not included.

## Supported setup

Windows 10 or later x64, .NET Framework 4.8, official WIRES-X 2.0.1.0, a genuine HRI-200 and the bundled com0com 3.0.0.0 x64 dependency. Initial profile capture requires an FTM-100 unless a compatible saved profile already exists. Use the same Windows account throughout setup, operation and removal.

## Release checks

| Area | Coverage |
|---|---|
| Build | Windows compilation with warnings as errors, script syntax and complete distribution-notice checks |
| Numbered interface | Main action order, compact setup, visible recovery/help, fitting guidance and real error-handler routing |
| Interrupted session | Refusal while an owner/adapter/native process remains, saved alias/scope checks, exclusive locking, retained evidence on partial failure and safe retry |
| Controller errors | Real isolated missing-setup failure produces a PID/time-bound error receipt |
| Protocol | Encoding, checksums, voice preservation, metadata profiles, native sequence compatibility and receive-capacity accounting against selected runtime binaries |
| YSF | Loopback UDP handover, old-room logout retries, idle boundaries, request ownership, active/saved destinations and configuration UI |
| Application | Setup, import, sign-in integration, status-worker lifecycle, tray behaviour and active-installation protections |
| Package | Extracted assembly hashes and complete upstream notices/source; matching versioned source and download checksums |

Hardware and recovery regression tests use isolated fixtures. They do not deliberately power-cycle a station or prove universal unattended recovery. Actual stop/start testing on an existing configured station is separate from a clean-PC installation or new profile capture.

## Important limits

- The installer is **unsigned**. A clean-PC driver installation and full uninstall/reinstall qualification are not established by package checks or an existing-station upgrade.
- A live owned process, fresh room proof and healthy YSF link establish connection state, not intelligible audio. This update does not claim a new two-way listening qualification or a cure for every intermittent audio fault.
- YSF unlink has no remote-removal acknowledgement. Retries cannot guarantee logout under total packet loss, and web rosters may lag.
- Queue pressure, missing headers and temporary native-room proof interruptions remain possible. No missing audio is invented or replayed.
- Secure Boot and Memory Integrity may block the legacy virtual-port dependency. Do not disable Windows security to force it to load.
- Other radios, receivers and WIRES-X versions, GPS accuracy and long-term reliability are not universally validated.
- Automatic operation requires interactive Windows sign-in, not pre-login boot. A retained record after an unclean shutdown requires explicit guarded recovery. Check actual reboot/sign-in behaviour on each PC before relying on unattended operation.

See the [user guide](../README.md), [recommended fixes](TROUBLESHOOTING.md) and [source build](DEVELOPMENT.md). Report reproducible faults through [GitHub Issues](https://github.com/M5LEE/wiresx-2-ysf-bridge/issues) rather than direct messages to M5LEE wherever possible.
