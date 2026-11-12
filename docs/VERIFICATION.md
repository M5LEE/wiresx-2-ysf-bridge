# Compatibility and testing

This document accompanies an experimental source snapshot of WiresX 2 YSF Bridge by M5LEE. Consult the [current user guide](https://github.com/M5LEE/wiresx-2-ysf-bridge#readme) and the selected release's notes for current requirements and features.

## Compatibility

The supported platform is Windows x64 with .NET Framework 4.8, official WIRES-X 2.0.1.0 and a genuine HRI-200. Initial radio-profile capture uses an FTM-100. Other radio models and WIRES-X builds are not confirmed compatible.

## Testing limits

The tests included with this snapshot exercise software behaviour using isolated fixtures. Passing them does not establish clear two-way audio, receiver display compatibility, driver installation on a clean PC, GPS accuracy or unattended recovery.

The legacy com0com driver may be blocked by Secure Boot or Memory Integrity. Setup checks device health; disabling Windows security is not supported. The installer is unsigned and the software is not certified for production or emergency communications.
