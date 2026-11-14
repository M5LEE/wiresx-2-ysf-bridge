# Bundled com0com dependency

com0com 3.0.0.0 is an independent GPL-licensed component, not M5LEE code and not Yaesu software. The bridge's GPLv3-or-later licence does not replace or upgrade its original upstream licence. The upstream GPL licence and complete unmodified upstream source archive are supplied alongside the dependency.

## Upstream downloads

- Project: https://sourceforge.net/projects/com0com/
- Signed distribution: https://downloads.sourceforge.net/project/com0com/com0com/3.0.0.0/com0com-3.0.0.0-i386-and-x64-signed.zip
- Distribution SHA256: `6e5d4359865277430d4ae88c73fb7e648a0ed8e81aea5002478179cfcb0bb0e1`
- Source: https://downloads.sourceforge.net/project/com0com/com0com/3.0.0.0/com0com-3.0.0.0.zip
- Source SHA256: `6751e911f73980b23cc878a456eb99d1dc6d0603c11c1d3ced109abe1c556380`

## Installation and compatibility

The bundled installer and management/driver files are unmodified upstream files. Their individual hashes are listed in `hashes.json`. Publisher signatures identify CyberCircuits, not M5LEE or Yaesu.

Installation occurs only after confirmation in Automatic setup. A healthy existing installation is reused. Removing the bridge does not remove the shared system driver or unrelated virtual-port pairs.

This legacy driver is not guaranteed compatible with Secure Boot or Memory Integrity. The bridge checks actual device health and does not disable Windows security or use the historical test-signing commands mentioned in the upstream readme.
