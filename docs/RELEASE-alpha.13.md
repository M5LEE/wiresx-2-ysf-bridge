# WiresX 2 YSF Bridge 0.1.0-alpha.13

## Simpler setup and clearer recovery

- Main buttons now follow **1. Set up bridge → 2. Check status → 3. Start bridge**.
- Compact setup numbers the YSF callsign, room and Save steps, with connection tools under Advanced setup.
- **What to do next** explains each state. **Help / recommended fixes** and actual setup errors give targeted advice.
- **Recover session** safely resolves a retained interrupted-session record after its processes have stopped. It validates the saved port names, keeps station settings and does not start the bridge.
- Controller failures include actionable error details. The bridge controller remains independent of the status window's lifetime.
- Setup, everyday operation, recovery and upgrade instructions now match the interface.

## Runtime selection

This release uses the established alpha.10 voice/protocol and YSF-link baseline. The experimental receive-recovery changes from alpha.11/12 are **not included**. This keeps the interface/recovery update separate from changes to audio handling. The earlier releases and their downloads remain available unchanged.

It remains an **unsigned experimental alpha**. Automated protocol, application and recovery checks do not establish universal audible quality, fresh-PC driver compatibility or unattended power-loss recovery. See [test coverage and limitations](VERIFICATION.md).

## Upgrade

Select **Stop bridge**, wait for cleanup, exit the tray/status app and close setup/settings windows. Install alpha.13 in the same directory and Windows account. Saved settings and connection profiles are retained. Reopen the launcher, select **2. Check status**, then **3. Start bridge**. Allow several minutes for WIRES-X login.

For a retained interrupted session, close WIRES-X/YMLAN normally and use **Recover session** before starting. Do not delete station data or ownership records.

## Support

**Please report bugs and setup problems through [GitHub Issues](https://github.com/M5LEE/wiresx-2-ysf-bridge/issues) so they can be tracked and help other users. Wherever possible, please avoid messaging M5LEE directly for support.**

[Setup and operation](../README.md) · [Recommended fixes](TROUBLESHOOTING.md)

Original current source is GPL-3.0-or-later; bundled dependencies retain their own terms. Previous releases retain their original licences. Downloads include the installer, matching source ZIP and SHA256 checksums.
