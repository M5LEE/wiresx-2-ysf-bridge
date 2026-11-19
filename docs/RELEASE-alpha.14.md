# WiresX 2 YSF Bridge 0.1.0-alpha.14

## Automatic recovery after reboot

With **Start automatically when I sign in to Windows** enabled, an interrupted bridge session no longer normally requires manual recovery:

1. Windows sign-in launches the bridge after the configured short delay.
2. The launcher safely recovers the previous session if its processes have gone and its saved connections still match.
3. After recovery completes, a fresh readiness check starts the bridge and WIRES-X automatically.
4. Allow several minutes for WIRES-X login and room reconnection.

Recovery is attempted once, not in a restart loop. Live sessions, changed connections and invalid ownership still block recovery. A failed recovery displays an error rather than starting anyway. The manual **Recover session** button remains recovery-only.

This is **interactive sign-in startup**, not a pre-login service. No Windows passwords, automatic-login configuration or security settings are changed.

## Verification and runtime

The recovery implementation passed an actual Windows reboot with the software left running: the bridge recovered, started and reconnected WIRES-X and YSF without manual Recover, Start or room-connect actions. The versioned release carries that same launcher implementation with updated version metadata. Windows regression tests cover automatic recovery, refusal paths, duplicate suppression and the existing application/runtime behaviour.

The exact packaged installer passed its owned-folder refusal and preservation checks; its extracted payload and matching source were verified. This release was not installed over the running test station. These checks do not establish a clean-PC installation, sudden power-cut recovery, universal hardware compatibility or new two-way listening quality.

The established alpha.10 voice/protocol and YSF-link binaries are retained. This update does not change audio handling or include alpha.11/12's experimental receive-recovery runtime. It remains an **unsigned experimental alpha**.

## Upgrade

Select **Stop bridge**, wait for cleanup, then **Exit status app (bridge stays running)** from the tray and close setup/settings windows. Install alpha.14 in the same directory and Windows account. Saved settings and connection profiles are retained. Reopen the launcher and check **Start automatically when I sign in to Windows** is enabled if you want automatic startup. Installing or enabling startup does not start the bridge immediately; use **3. Start bridge** for the current session.

If recovery refuses, follow the displayed recommendation. Do not delete station data or ownership records to force a start.

## Support

**Please report bugs and setup problems through [GitHub Issues](https://github.com/M5LEE/wiresx-2-ysf-bridge/issues) so they can be tracked and help other users. Wherever possible, please avoid messaging M5LEE directly for support.**

[Setup and operation](../README.md) · [Recommended fixes](TROUBLESHOOTING.md) · [Test coverage](VERIFICATION.md)

Original current source is GPL-3.0-or-later; bundled dependencies retain their own terms. Previous releases and their downloads remain unchanged. Downloads include the installer, matching source ZIP and SHA256 checksums.
