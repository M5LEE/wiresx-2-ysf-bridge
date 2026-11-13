# Third-party rights and interoperability notice

**WIRES-X, HRI-200, FTM-100 and Yaesu names, software, drivers, firmware and trademarks remain the property of their respective copyright and trademark owners. All applicable third-party rights are reserved.**

This is independent experimental software by M5LEE. It is not an official Yaesu product and is not affiliated with, sponsored by or endorsed by Yaesu or the WIRES-X software owners. The project's MIT licence grants no rights over their software, firmware, service, licences or trademarks.

## Not included

The installer and source bundle do **not** include proprietary WIRES-X executables or DLLs, HRI-200 firmware, Yaesu drivers, Microsoft .NET redistributables, another operator's captured radio profile, credentials or recordings. Obtain these from legitimate suppliers and comply with their licences and service terms. Do not bypass driver signing, Secure Boot, Memory Integrity or Windows security controls to install an old serial driver.

## Included GPL dependency: com0com

com0com 3.0.0.0, the upstream signed x64 installer and its management/driver files, are bundled separately under the GNU GPL, not under M5LEE's MIT licence. Copyright remains with Vyacheslav Frolov and the respective com0com contributors; retain the individual upstream copyright and licence headers. The complete upstream source archive, GPL licence, original readme, origin URLs and file hashes are supplied in `vendor/com0com/` in both the installed payload and source release. See `vendor/com0com/ORIGIN.md`. The upstream signatures identify CyberCircuits; they are not M5LEE or Yaesu signatures. This is not a guarantee of compatibility with modern Windows kernel security policies. The setup verifies signature/integrity and actual port health and never changes Windows security settings. No com0com source/binary code has been modified.

The runtime supports a hash-pinned WIRES-X 2.0.1.0 executable for the experimental observer. A hash identifies a supported local installation; it does not redistribute or license that executable. A different build is refused rather than silently treated as compatible.

The [WIRES-X terms review](https://github.com/M5LEE/wiresx-2-ysf-bridge/blob/main/docs/YAESU-TERMS-REVIEW.md) records the exact installer EULA checked and the limits of the available server-agreement evidence. No Yaesu approval or entitlement to server access is claimed.

## Protocol research and references

The C# protocol implementation and diagnostic tools were developed for interoperability research. Independent test vectors/reference behaviour were compared with the G4KLX YSF ecosystem. No G4KLX/Yaesu executable, source tree or vendor implementation is bundled. Golay, CRC, convolution and interleaving routines implement the mathematical protocol operations; the package does not transcode or include an AMBE vocoder.

The reflector catalogue is downloaded on demand from the Pi-Star-published DVRef-derived YSF host list. Directory content and its availability remain under the control of its publishers. A catalogue is not bundled and the project does not claim ownership of those records. Updating it sends a normal HTTPS request to the published feed; optional support links open a browser only when clicked.

This notice is attribution and a statement of packaging scope, **not legal advice or a guarantee that an operator's planned use complies with vendor/service terms or local radio regulations**. Operators must assess those obligations independently. Retain any applicable third-party notices when modifying or adding dependencies.
