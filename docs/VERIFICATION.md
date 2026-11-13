# Compatibility and testing

**WiresX 2 YSF Bridge 0.1.0-alpha.9** is an experimental release. This page summarises its test coverage and compatibility limits.

## Supported setup

- Windows 10 or later, x64, with .NET Framework 4.8.
- Official WIRES-X 2.0.1.0 and a genuine HRI-200.
- FTM-100 for initial radio-profile capture, or a compatible existing bridge profile.
- The bundled com0com 3.0.0.0 x64 virtual-port dependency.
- The same Windows account for setup, operation, startup configuration and removal.

## Alpha.9 validation

| Area | Coverage |
|---|---|
| Build | Windows compilation with warnings treated as errors |
| Protocol | Frame encoding, checksums, callsign layout, optional data profiles, sequence handling and receive-drop accounting |
| C4FM metadata | 16,167 profile checks covering absent/short/full data, supported envelopes, identity fields and transmission boundaries |
| Voice preservation | Synthetic comparisons of voice bytes, packet timing, sequence fields, serial replies and the reverse receive path |
| Application | Configuration, setup, import, startup, status-helper lifecycle, tray behaviour and active-installation guards |
| Release files | Extracted installer payload checked against its assembly hash manifest; published assets downloaded and checksum-verified |
| Installer guard | Exact alpha.9 EXE refused an isolated destination containing a bridge ownership record, without copying the application |
| Live station | Audio and Yaesu/DMR caller display reported working after the alpha.9 metadata correction |

The automated device and startup tests use isolated fixtures and simulated actions. They do not perform a fresh driver installation or a full station startup. Live feedback relates to the tested station, not every receiver or network path. DMR display observations do not imply a native DMR interface in this application.

## Compatibility limits

- **The alpha.9 installer is unsigned.** A complete install/upgrade/uninstall cycle has not been repeated for this exact release, and clean-PC installation is not fully validated.
- Secure Boot and Memory Integrity may prevent the legacy com0com driver from loading. A valid publisher signature alone does not establish compatibility. Setup checks actual device health; disabling Windows security is not a supported workaround.
- First-time capture and setup on independent stations, other radio models and other WIRES-X versions are not confirmed compatible.
- Automatic startup requires interactive sign-in. Unattended power-loss recovery and real reboot/sign-in behaviour need checking on each station.
- Broad two-way audio quality, universal caller-display compatibility, GPS accuracy and long-term reliability are not certified. Connection status alone does not establish intelligible audio.

For installation and operation, see the [user guide](../README.md). Automated tests run as part of the [source build](DEVELOPMENT.md).
