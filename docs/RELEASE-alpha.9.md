# WiresX 2 YSF Bridge — 0.1.0-alpha.9

Experimental Windows release by **M5LEE**, linking the room currently connected in official WIRES-X to a YSF reflector.

## What's new

- Corrected C4FM metadata cycles for caller callsign display.
- Preserved supported native caller information and optional data.
- Simpler normal setup: YSF bridge callsign and destination room.
- Lower-overhead connection-status checks.
- Clearer accounting of incoming frames dropped when the receive queue is full.
- Includes tray status and optional Windows sign-in startup.

## Downloads

- [**Setup.exe**](https://github.com/M5LEE/wiresx-2-ysf-bridge/releases/download/v0.1.0-alpha.9/WiresX-2-YSF-Bridge-0.1.0-alpha.9-Setup.exe) — Windows x64 installer.
- [**Source.zip**](https://github.com/M5LEE/wiresx-2-ysf-bridge/releases/download/v0.1.0-alpha.9/WiresX-2-YSF-Bridge-0.1.0-alpha.9-Source.zip) — Alpha.9 source snapshot.
- [**SHA256SUMS.txt**](https://github.com/M5LEE/wiresx-2-ysf-bridge/releases/download/v0.1.0-alpha.9/WiresX-2-YSF-Bridge-0.1.0-alpha.9-SHA256SUMS.txt) — checksums for the installer and source ZIP.

Downloads currently require signing in to a GitHub account with access to this private repository.

WIRES-X must already be installed, configured and working with a genuine HRI-200. The [user guide](https://github.com/M5LEE/wiresx-2-ysf-bridge#readme) covers requirements, first-time setup and operation.

## Upgrading

Stop the bridge, wait for cleanup, exit its tray/status application and close setup/settings windows before upgrading. Running installations are refused rather than automatically stopped. Existing station settings and profiles are retained. Do not run two bridges together.

Already running the alpha.9 callsign correction? An immediate reinstall is unnecessary.

## Known limitations

The installer is **unsigned**, and this is an **alpha**, not a certified production release. Clean-PC setup, legacy driver compatibility with current Windows security, receiver compatibility, GPS accuracy and long-term reliability are not fully validated. See [compatibility and testing](https://github.com/M5LEE/wiresx-2-ysf-bridge/blob/main/docs/VERIFICATION.md).
