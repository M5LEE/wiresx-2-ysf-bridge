# WiresX 2 YSF Bridge 0.1.0-alpha.11

**By M5LEE · Experimental Windows x64 prerelease**

## What's new

- **Back-to-back overs:** the next valid receive header can wait while the previous over finishes, without increasing the four-frame queue limit.
- **Safer recovery after interruptions:** bounded receive recovery handles short gaps and plausible sequence advances without generating silence, repeating audio or replaying old queued voice.
- **Stronger room-state handling:** coordinated status-file access reduces transient read failures; connection tracking distinguishes genuine disconnects and same-room reconnects.
- **Preserved safety boundaries:** Stop, room changes, stale or mismatched connection proof, blocked stream boundaries and intervening transmissions clear old receive context.
- **Queue-pressure recovery:** known local capacity drops no longer leave sequence tracking behind and suppress the remainder of an otherwise valid over.
- Existing live YSF room switching, old-room logout, caller metadata, tray controls and optional Windows sign-in startup remain available.

## Downloads

- `WiresX-2-YSF-Bridge-0.1.0-alpha.11-Setup.exe` — Windows x64 installer.
- `WiresX-2-YSF-Bridge-0.1.0-alpha.11-Source.zip` — matching source snapshot, dependency source and notices.
- `WiresX-2-YSF-Bridge-0.1.0-alpha.11-SHA256SUMS.txt` — installer and source checksums.

Downloads remain private and require an authorised GitHub account. The previous [alpha.10 release](https://github.com/M5LEE/wiresx-2-ysf-bridge/releases/tag/v0.1.0-alpha.10) remains available.

## Installation and upgrade

Official WIRES-X must already be installed, configured and working with a genuine HRI-200. Bridge setup asks for the YSF bridge callsign and destination and follows the room connected in WIRES-X. See the [user guide](../README.md) for setup and profile requirements.

Before upgrading, **Stop bridge**, wait for cleanup, then **Exit status app** and close setup/configuration windows. The installer refuses an active target rather than stopping it. Station settings and compatible saved profiles are retained. Do not copy individual components over a running installation.

## Validation and limits

The selected runtime passes the Windows build and protocol, receive-recovery, room-proof, configuration, actual adapter dispatch, loopback UDP handover/logout and lifecycle tests. A healthy-traffic comparison matches the previous reference version's complete output bytes and timestamps in both directions. The exact installer payload and owned-destination refusal are checked separately.

**This remains an alpha, not a beta. Live listening and extended operation of the receive-recovery changes are pending.** Automated checks are not a substitute for receiver listening, and earlier-version observations do not validate this version. The installer is unsigned; a full clean-PC install/upgrade/uninstall cycle, broad receiver compatibility and unattended recovery are not certified. Do not disable Windows security to force the legacy virtual-port driver to load.

See [compatibility and testing](VERIFICATION.md), [receive recovery](RECEIVE-RECOVERY.md) and [live YSF changes](LIVE-YSF-APPLY.md).

Original bridge contributions are MIT-licensed by M5LEE. Bundled com0com remains separately GPL-licensed. This is independent software, not an official or endorsed Yaesu product; Yaesu software is not included.
