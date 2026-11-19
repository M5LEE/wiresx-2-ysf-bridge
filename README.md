# WiresX 2 YSF Bridge

**By M5LEE · 0.1.0-alpha.14 · Free, experimental Windows software**

Connect the room currently linked in **official WIRES-X** to a **YSF reflector**, using your existing WIRES-X installation and genuine HRI-200. The bridge carries digital voice and supported caller information between the two networks.

**Set up WIRES-X first.** Keep its existing account and room settings. Normal bridge setup asks for your **YSF bridge callsign** and **YSF destination room**, not another WIRES-X login or gateway ID. The bridge follows whichever room is connected in WIRES-X.

## Downloads

| File | Download |
|---|---|
| Windows x64 installer | [Setup.exe](https://github.com/M5LEE/wiresx-2-ysf-bridge/releases/download/v0.1.0-alpha.14/WiresX-2-YSF-Bridge-0.1.0-alpha.14-Setup.exe) |
| Matching source | [Source.zip](https://github.com/M5LEE/wiresx-2-ysf-bridge/releases/download/v0.1.0-alpha.14/WiresX-2-YSF-Bridge-0.1.0-alpha.14-Source.zip) |
| File checksums | [SHA256SUMS.txt](https://github.com/M5LEE/wiresx-2-ysf-bridge/releases/download/v0.1.0-alpha.14/WiresX-2-YSF-Bridge-0.1.0-alpha.14-SHA256SUMS.txt) |

[Release page](https://github.com/M5LEE/wiresx-2-ysf-bridge/releases/tag/v0.1.0-alpha.14) · [What changed](docs/RELEASE-alpha.14.md) · [Troubleshooting](docs/TROUBLESHOOTING.md)

Downloads are public. This is still an **unsigned alpha**, not a beta or a certified production system. Alpha.14 adds automatic interrupted-session recovery at Windows sign-in, retaining the numbered setup and established alpha.10 voice runtime. It does **not** include the experimental receive-recovery changes from alpha.11/12. Previous releases remain available.

## Before you install

You need:

- Windows 10 or later, **64-bit**, with **.NET Framework 4.8**.
- Official **WIRES-X 2.0.1.0**, configured and working, with the Yaesu HRI-200 driver installed.
- A genuine **HRI-200** connected to the PC.
- An **FTM-100 for initial connection-profile capture**, unless you already have a compatible saved bridge profile.
- Administrator approval when requested. Use the same Windows account for setup, operation, startup configuration and removal.

This is an independent project, not an official Yaesu product. Official WIRES-X and Yaesu drivers are obtained separately. An existing WIRES-X installation alone does not provide the bridge's saved connection profile.

## Install and follow 1 → 2 → 3

Run **WiresX-2-YSF-Bridge-0.1.0-alpha.14-Setup.exe**. Leave **Set up my bridge** selected on the final page, or open **Bridge launcher** from the Start menu.

### 1. Set up bridge

In the setup window:

1. **Your YSF callsign:** enter the callsign you want the bridge to use on YSF.
2. **Choose a YSF room:** open the room chooser, select your destination and its required DG-ID, click **Save config**, then close the chooser.
3. **Save setup:** save the callsign and connection settings. Select **Back to bridge** afterwards.

**First use only:** if the connection is not ready or Save is disabled, tick **Advanced setup** and choose **Automatic setup**. After confirmation it detects the genuine HRI-200 and sets up the virtual-port connection using the bundled com0com dependency. A compatible existing connection is reused; do not guess COM numbers.

If you do not have a valid connection profile, connect and power on your FTM-100 and choose **Create connection profile** under Advanced setup. Follow the ownership confirmation and wait about two minutes. Capture may close and reopen WIRES-X; PTT and voice forwarding are blocked during capture. Reopen setup to check the result. Alternatively, **Import existing settings** can reuse a compatible previous bridge folder while retaining your chosen YSF callsign.

**Before normal bridge operation:** close WIRES-X completely, turn the radio off and disconnect its cable from the HRI-200. Leave the HRI-200 powered and connected to the PC by USB. Keep your WIRES-X account and room settings unchanged. Disable separate WIRES-X/YMLAN automatic startup so it does not compete with the bridge's startup order. Complete any required radio-profile capture before disconnecting the radio.

### 2. Check status

Select **2. Check status** in the bridge window. The **What to do next** panel explains anything missing and recommends the next action. This check does not start or stop the bridge.

If it says **Needs attention** after a reboot or interrupted session, follow [Recover after an interrupted session](#recover-after-an-interrupted-session). Do not delete settings or reinstall just to clear this message.

### 3. Start bridge

Select **3. Start bridge** once. The bridge prepares its connection and **launches WIRES-X automatically**. Do not open WIRES-X separately or repeatedly press Start. Allow several minutes for the transceiver handshake, login and room connection.

**Running** means the owned bridge is live, its WIRES-X room proof is fresh and the YSF link is healthy. Confirm actual two-way audio with a listener; green status alone does not prove audio quality.

## Everyday operation

- Change the WIRES-X room in official WIRES-X as usual; the bridge follows it.
- To change the YSF side while running, select **Change YSF room**, choose a destination/DG-ID and click **Apply YSF room**. The bridge waits for a quiet point, logs out of the old reflector and joins the new one without restarting WIRES-X.
- Check **Active YSF** for the running destination. **Save config** alone saves the next-start selection; it does not switch an active link. A failed switch reports the problem and attempts to restore the previous destination. See [live YSF destination changes](docs/LIVE-YSF-APPLY.md).
- Use **Stop bridge** and confirm when you want to stop. Wait for cleanup before restarting, upgrading or disconnecting equipment.
- **Closing the status window does not stop the bridge.** It hides to the notification area. Double-click the tray icon to reopen it. **Exit status app (bridge stays running)** closes only the status application.

The bridge runs until you stop it or a safety fault occurs. It does not use a normal session countdown.

## Recover after an interrupted session

A reboot or power interruption can leave a record of the previous session. With **Start automatically when I sign in to Windows** enabled, alpha.14 checks and recovers a safely recoverable old session automatically, then starts the bridge and WIRES-X. You do not normally need to click Recover or Start after signing in.

If automatic startup is disabled, or recovery reports a genuine conflict, use the manual procedure:

1. Close **WIRES-X** and its **YMLAN** companion normally.
2. In the bridge window, select **Recover session** and confirm.
3. Select **2. Check status**, then **3. Start bridge** when ready.

Recovery checks that the old processes are gone and restores only the bridge's two saved port names. It keeps your callsign, room settings and connection profile. The manual **Recover session** button does not start anything; enabled sign-in startup continues to Start only after recovery succeeds and a fresh readiness check passes. If recovery refuses, follow its error message; do not delete the ownership record or force-close unknown processes. See [recommended fixes](docs/TROUBLESHOOTING.md).

## Automatic startup

Tick **Start automatically when I sign in to Windows** in the bridge window. At your next interactive sign-in, the launcher starts the adapter before WIRES-X after a short delay. Enabling this option does not start the bridge immediately.

Startup is optional and initially off. It backs up and replaces matching WIRES-X/YMLAN Startup shortcuts; disabling it restores them. Conflicting startup entries are reported for review. It is **not a pre-login service** and does not configure Windows automatic sign-in. Automatic recovery runs once per sign-in launch and will not override live sessions, changed port names or invalid ownership records. Allow several minutes for WIRES-X login and room reconnection; do not repeatedly restart it while it says Connecting. Test reboot/sign-in on your own PC before relying on unattended operation.

## Upgrade or uninstall

Select **Stop bridge**, wait for cleanup, then **Exit status app (bridge stays running)** from the tray and close setup/settings windows. Run the new installer, keeping the same installation directory and Windows account. An active installation is refused rather than forcibly stopped.

Normal uninstall keeps your station settings and profile, shared virtual-port drivers/devices and official WIRES-X. Do not delete station data to troubleshoot an upgrade. Avoid running two bridge installations at once.

## Problems and support

**Please report bugs and setup problems through [GitHub Issues](https://github.com/M5LEE/wiresx-2-ysf-bridge/issues) so they can be tracked and help other users. Wherever possible, please avoid messaging M5LEE directly for support.**

First read **What to do next** or **Help / recommended fixes** in the application, then the [troubleshooting guide](docs/TROUBLESHOOTING.md). Search existing issues before opening a new one. Include the bridge version, Windows version, step you were performing, exact error and what you expected. Redact screenshots and never post passwords, private connection profiles or location data.

## Limitations and source

The installer is unsigned. Fresh-PC setup, universal receiver compatibility, GPS accuracy and long-term reliability are not fully validated. The legacy virtual-port driver may be blocked by Secure Boot or Memory Integrity; **do not disable Windows security** to force it to load. Do not rely on this experimental bridge for emergency communications.

- [Compatibility and test coverage](docs/VERIFICATION.md)
- [Building from source](docs/DEVELOPMENT.md)
- [C4FM metadata format](docs/C4FM-METADATA-PROFILES.md)
- [Matching source tag](https://github.com/M5LEE/wiresx-2-ysf-bridge/tree/v0.1.0-alpha.14)
- [Third-party notices](THIRD_PARTY_NOTICES.md)

## Licence and optional donations

Copyright (c) **2026 M5LEE**. Current original contributions are licensed under the [GNU General Public License, version 3 or later](LICENSE) (`GPL-3.0-or-later`), **AS IS and without warranty**. Bundled com0com retains its separate upstream licence and source. Earlier alpha.11 and prior downloads retain their original MIT permissions for the bridge code; old downloads and tags are not replaced.

Donations to the **CumbriaCQ network** are optional, not licence fees or feature unlocks:

- PayPal: https://www.paypal.com/donate?campaign_id=HQ9VSCMVLLYPC
- Support information: https://cumbriacq.com/donate-support/
