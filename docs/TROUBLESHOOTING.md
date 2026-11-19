# Recommended fixes

Use **2. Check status** and read **What to do next** before changing anything. Setup also has **Help / recommended fixes**. Keep official WIRES-X account settings and saved bridge data intact.

| Message or symptom | Recommended action |
|---|---|
| Setup required / Save disabled | Open **1. Set up bridge**. Enter your YSF callsign and destination. On first use, run **Advanced setup > Automatic setup**, then create or import your own connection profile. Select **3. Save setup**, **Back to bridge**, then **2. Check status**. |
| Starting / waiting for handshake | Allow several minutes without pressing Start again. Check the HRI-200 USB connection and official WIRES-X window. The bridge opens WIRES-X itself. |
| Connecting / no room yet | Allow login to finish. Read any error in WIRES-X, check Internet access and connect to a room there. Keep account settings unchanged. |
| Needs attention after reboot | Close WIRES-X and YMLAN normally. Select **Recover session**, confirm, then **2. Check status**. Start only when ready. Recovery keeps saved setup. |
| Recovery refuses because a session is alive | Use that bridge's own Stop control and wait for cleanup. Recovery deliberately refuses live owners. Do not delete its record or force-kill unknown processes. |
| Recovery still refuses / unknown port names | Keep the exact error and report an issue. Do not rename unrelated devices, clear station data or run Automatic setup over an unresolved session. |
| Other session | Open the status app belonging to the running installation and stop it normally before changing installations. |
| WIRES-X connected, YSF unavailable | Check Internet access and whether the selected YSF room is online. Use **Change YSF room** to inspect the destination and required DG-ID. Recheck status. |
| Status update late | Click **2. Check status**. A late update is not proof that audio stopped. If it persists, report the message instead of immediately reinstalling. |
| Room list will not load | Check Internet access, reopen the room chooser and retry. Use a valid cached destination if available; do not guess endpoints. |
| Invalid or duplicate COM ports | The physical port and both virtual endpoints must be different. Use **Advanced setup > Automatic setup** instead of guessing. |
| HRI-200 not detected | Check its USB cable and official Yaesu driver in Device Manager. Retry Automatic setup only after resolving that device's fault. |
| Driver blocked / restart requested | Finish a Windows-requested restart and check Device Manager. Do not disable Secure Boot, Memory Integrity or signature enforcement. Report compatibility problems if the signed dependency remains blocked. |
| Missing connection profile | Create or import a profile from your own supported station under Advanced setup. WIRES-X login settings are not a radio profile. |
| Controller error | Read the displayed error and recommended fix. Check the HRI-200 and WIRES-X window. Keep the error if it repeats; do not clear evidence by deleting setup. |
| Upgrade refused | Stop bridge, wait for cleanup, exit its tray/status app and close setup/settings windows. Retry in the same Windows account. |
| Green status but poor/no audio | Note the direction, UTC time, room and whether one caller or all callers are affected. Compare an actual listener's result; a connection indicator cannot certify audio quality. |

## Report an issue

Please use [GitHub Issues](https://github.com/M5LEE/wiresx-2-ysf-bridge/issues) so problems can be tracked and help other users. Wherever possible, please avoid messaging M5LEE directly for support.

Search existing issues first. Include the bridge/Windows/WIRES-X versions, setup or upgrade context, exact numbered step, error message, expected result and steps to reproduce. For audio faults, include direction and time rather than assuming every caller has the same problem. Redact screenshots. Never attach passwords, private station/profile files, speech recordings or location data.

[Return to setup and operation](../README.md)
