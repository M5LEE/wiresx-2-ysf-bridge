# WiresX 2 YSF Bridge

**By M5LEE · 0.1.0-alpha.8 · Experimental Windows software**

A Windows bridge connecting an existing official WIRES-X/HRI-200 station to a YSF reflector. This is a historical source snapshot; features and setup controls vary by version.

- [Current user guide](https://github.com/M5LEE/wiresx-2-ysf-bridge#readme)
- [Downloads and release notes](https://github.com/M5LEE/wiresx-2-ysf-bridge/releases)

## Requirements and operation

Official WIRES-X must already be installed, configured and working with a genuine HRI-200. The supported setup uses Windows x64, .NET Framework 4.8 and WIRES-X 2.0.1.0. Initial local radio-profile capture requires an FTM-100; the radio is powered off and the HRI-200 remains connected during bridge operation.

Configure the YSF-side identity and destination using this version's setup tools. Start and stop the bridge explicitly. Do not run two bridge instances together. Stop the bridge and close its windows before upgrading or removing it.

## Limitations

This snapshot is experimental, unsigned and provided AS IS. Receiver compatibility, audio quality, first-time setup and legacy virtual-port driver compatibility are not universally validated. Windows security must not be disabled to load a driver. Do not use this software for emergency communications.

## Licence

Original project code is [MIT licensed](LICENSE), copyright (c) 2026 M5LEE. The bundled com0com component retains its own licence and upstream source. See [third-party notices](THIRD_PARTY_NOTICES.md).
