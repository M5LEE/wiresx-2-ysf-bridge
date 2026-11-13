# WiresX 2 YSF Bridge 0.1.0-alpha.10

**By M5LEE · Experimental Windows x64 prerelease**

## What's new

- **Apply YSF room** changes the running YSF destination between overs without restarting official WIRES-X, the adapter or the serial connection. **Active YSF** shows the actual running selection separately from saved settings.
- **Stronger old-room logout:** keepalives stop during handover, three spaced unlink requests precede the new join, and a failed destination is cleaned up before rollback. Forwarding stays closed until the selected reflector acknowledges.
- **Audio packet handling improvements:** supported native counter compatibility and adapter scheduling/dispatch corrections retain the encoded voice data and existing C4FM metadata profiles.
- Existing tray controls, optional interactive Windows sign-in startup, automatic connection setup and protected station-data reuse remain available.
- Updated user/technical documentation and retained com0com licence, source archive and upstream notices.

## Downloads

- `WiresX-2-YSF-Bridge-0.1.0-alpha.10-Setup.exe` — Windows x64 installer.
- `WiresX-2-YSF-Bridge-0.1.0-alpha.10-Source.zip` — matching source snapshot and bundled dependency source/notices.
- `WiresX-2-YSF-Bridge-0.1.0-alpha.10-SHA256SUMS.txt` — installer and source checksums.

The repository and downloads remain private; sign in to GitHub with an authorised account.

## Installation and upgrade

Set up official WIRES-X first, with a working genuine HRI-200 installation. Bridge setup uses the existing WIRES-X account and asks for the YSF bridge callsign and destination. See the [user guide](../README.md) for first-time setup and profile requirements.

Before upgrading, **Stop bridge**, wait for cleanup, then **Exit status app** and close setup/configuration windows. The installer refuses an active target rather than stopping it. Existing station data and compatible profiles are retained. After this one stopped upgrade, normal YSF destination changes use **Apply YSF room** without another WIRES-X restart. **Save config** alone affects the next start.

## Validation and limits

The selected payload passes Windows compilation and protocol, metadata, actual adapter, real UDP handover/logout, configuration UI, startup and lifecycle tests. Its voice engine is the unchanged runtime used for the latest live listening checks. Installer payload hashes and safe refusal of an owned destination are checked separately from station operation.

This is an **unsigned alpha**, not a certified production release. A full clean-PC installation, exact-release install/upgrade/uninstall cycle, universal receiver compatibility and unattended recovery are not certified. The bundled legacy driver may be blocked by modern Windows security; disabling that security is not supported.

YSF has no standard acknowledgement proving old-server removal. Logout retries improve reliability but cannot guarantee delivery if every retry is lost. Reflector dashboard lists may update late. Occasional queue-pressure/admission events remain diagnostic limitations; good listening results do not prove every path loss-free. See [compatibility and testing](VERIFICATION.md) and [live YSF changes](LIVE-YSF-APPLY.md).

Original bridge contributions are MIT-licensed by M5LEE. Bundled com0com remains separately GPL-licensed. This is independent software, not an official or endorsed Yaesu product; Yaesu software is not included.
