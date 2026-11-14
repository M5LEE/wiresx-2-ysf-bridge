# WiresX 2 YSF Bridge 0.1.0-alpha.12

**By M5LEE · Experimental Windows x64 prerelease**

## What's new

- **GPLv3-or-later distribution:** the installer and matching source include the complete GNU GPL version 3 licence and the project's explicit version-3-or-later grant.
- **Existing-radio tester guide:** keep your WIRES-X account, room and radio settings; disable separate WIRES-X startup, close WIRES-X before disconnecting the powered-off radio from the HRI-200, then use Start bridge. The bridge launches WIRES-X automatically. Complete first-time bridge setup and any required profile capture before disconnecting the radio.
- **Updated installer and packaged documentation:** public download instructions, licence notices and the tester guide are included with the installed application.
- **Build-test isolation:** the setup UI test locates its fixture data-root assignment structurally rather than by a fixed source-line number, with explicit checks before loading the UI.
- **No new audio or protocol changes:** the selected protocol and configuration libraries are identical to alpha.11. Its back-to-back over handling, bounded receive recovery, live YSF switching, caller information and optional Windows sign-in startup are retained.

## Downloads

- [WiresX-2-YSF-Bridge-0.1.0-alpha.12-Setup.exe](https://github.com/M5LEE/wiresx-2-ysf-bridge/releases/download/v0.1.0-alpha.12/WiresX-2-YSF-Bridge-0.1.0-alpha.12-Setup.exe) — Windows x64 installer.
- [WiresX-2-YSF-Bridge-0.1.0-alpha.12-Source.zip](https://github.com/M5LEE/wiresx-2-ysf-bridge/releases/download/v0.1.0-alpha.12/WiresX-2-YSF-Bridge-0.1.0-alpha.12-Source.zip) — matching source, build instructions and dependency source/notices.
- [WiresX-2-YSF-Bridge-0.1.0-alpha.12-SHA256SUMS.txt](https://github.com/M5LEE/wiresx-2-ysf-bridge/releases/download/v0.1.0-alpha.12/WiresX-2-YSF-Bridge-0.1.0-alpha.12-SHA256SUMS.txt) — installer and source checksums.

Downloads are public; no GitHub sign-in is required. The previous [alpha.11 release](https://github.com/M5LEE/wiresx-2-ysf-bridge/releases/tag/v0.1.0-alpha.11) remains available unchanged.

## Installation and upgrade

Official WIRES-X must already be installed, configured and working with a genuine HRI-200. Bridge setup asks for the YSF bridge callsign and destination and follows the room connected in WIRES-X. A supported local connection profile is still required. See the [user guide](../README.md).

Before upgrading, **Stop bridge**, wait for cleanup, then **Exit status app** and close setup/configuration windows. The installer refuses an active target rather than stopping it. Station settings and compatible saved profiles are retained. Do not copy individual components over a running installation.

## Validation and limits

The selected package is checked with the Windows build and protocol, receive-recovery, room-proof, configuration, actual adapter dispatch, loopback UDP handover/logout and lifecycle tests. Licence/distribution tests cover complete GPL text, Windows line endings, missing/altered notices and dependency source integrity. The exact installer payload and its safe refusal of an isolated owned destination are checked separately; published files are downloaded again and checked against their SHA256 hashes.

**This remains an alpha, not a beta. Live listening and extended operation of the receive-recovery changes remain pending.** The installer is unsigned. A full clean-PC install/upgrade/uninstall cycle, broad receiver compatibility and unattended recovery are not certified. Do not disable Windows security to force the legacy virtual-port driver to load.

See [compatibility and testing](VERIFICATION.md), [receive recovery](RECEIVE-RECOVERY.md) and [live YSF changes](LIVE-YSF-APPLY.md).

## Licence

Original bridge contributions in alpha.12 are **GNU GPL version 3 or later (`GPL-3.0-or-later`)**, copyright (c) 2026 M5LEE, provided AS IS and without warranty. Alpha.11 and earlier downloads retain their original MIT permissions for the bridge code. Bundled com0com keeps its separate upstream licence and corresponding source. This is independent software, not an official or endorsed Yaesu product; Yaesu software is not included.
