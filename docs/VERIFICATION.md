# Compatibility and testing

**WiresX 2 YSF Bridge 0.1.0-alpha.12** is an experimental release. This page summarises its test coverage and compatibility limits. Alpha.12 updates licensing, documentation and versioned packaging; its selected protocol and configuration libraries are byte-identical to alpha.11. The receive-recovery changes have automated validation; live listening and extended operation of this version remain pending.

## Supported setup

- Windows 10 or later, x64, with .NET Framework 4.8.
- Official WIRES-X 2.0.1.0 and a genuine HRI-200.
- FTM-100 for initial radio-profile capture, or a compatible existing bridge profile.
- The bundled com0com 3.0.0.0 x64 virtual-port dependency.
- The same Windows account for setup, operation, startup configuration and removal.

## Alpha.12 validation

| Area | Coverage |
|---|---|
| Build | Windows compilation with warnings treated as errors |
| Protocol | Frame encoding, checksums, callsign layout, optional data profiles, sequence handling and receive-drop accounting |
| C4FM metadata | 16,167 profile checks covering absent/short/full data, supported envelopes, identity fields and transmission boundaries |
| Voice preservation | Synthetic comparisons of voice bytes, packet timing, sequence fields, serial replies and the reverse receive path |
| Application | Configuration, setup, import, startup, status-helper lifecycle, tray behaviour and active-installation guards |
| Audio packet handling | Native counter compatibility and production adapter scheduling/dispatch regressions, using the selected voice runtime |
| Receive recovery | Back-to-back headers, bounded queues, gaps, sequence jumps, overflow recovery and stale-context rejection |
| Room proof | Same-room reconnect detection, process binding, actual adapter/observer state logic and concurrent file-publication tests |
| Healthy-traffic comparison | The unchanged selected protocol previously matched 4,554 timestamped serial/network events against the alpha.10 reference in both directions and measured/unmeasured receive modes; its trace regression is rerun for this package |
| Live YSF changes | Real loopback UDP handover, idle boundaries, request ownership, active/saved state and actual configuration-button tests |
| Old-room logout | Dropped first/first-two unlink packets, keepalive suppression, failed-target cleanup and rollback tests |
| Release files | Extracted installer payload checked against its assembly hash manifest; published assets downloaded and checksum-verified |
| Licence and dependency notices | 26 regression checks cover complete GPLv3 text, Windows line endings, missing/altered notices and upstream dependency source integrity |
| Installer guard | Exact alpha.12 EXE checked for safe refusal of an isolated destination containing a bridge ownership record, without copying the application |
| Live station | Alpha.12 listening and extended operation remain pending; earlier-version observations are not acceptance of this package |

The automated device and startup tests use isolated fixtures and simulated actions. They do not perform a fresh driver installation or a full station startup. Earlier live feedback relates to the tested version and station, not every receiver or network path. DMR display observations do not imply a native DMR interface in this application.

## Compatibility limits

- **The alpha.12 installer is unsigned.** A complete install/upgrade/uninstall cycle has not been repeated for this exact release, and clean-PC installation is not fully validated.
- YSF unlink has no standard remote-removal acknowledgement. Retries improve logout reliability but cannot guarantee delivery when every retry is lost; reflector web lists can be delayed.
- Occasional queue-pressure and native admission events remain diagnostic limitations. Clean observed packet timing and good listening results do not establish zero loss on every path.
- Secure Boot and Memory Integrity may prevent the legacy com0com driver from loading. A valid publisher signature alone does not establish compatibility. Setup checks actual device health; disabling Windows security is not a supported workaround.
- First-time capture and setup on independent stations, other radio models and other WIRES-X versions are not confirmed compatible.
- Automatic startup requires interactive sign-in. Unattended power-loss recovery and real reboot/sign-in behaviour need checking on each station.
- Broad two-way audio quality, universal caller-display compatibility, GPS accuracy and long-term reliability are not certified. Connection status alone does not establish intelligible audio.

For installation and operation, see the [user guide](../README.md). Automated tests run as part of the [source build](DEVELOPMENT.md).
