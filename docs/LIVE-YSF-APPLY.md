# Live YSF destination changes

Live YSF destination changes are included in **0.1.0-alpha.10**. Earlier installers require an upgrade to use this feature.

## Operation

1. Open the bridge configuration window and select a YSF room.
2. Set its DG-ID and DG-ID 0 acceptance policy as required by that reflector.
3. Choose **Apply YSF room**. This saves the selection and sends a request to the running bridge.
4. Wait for the result. The **Active YSF** label reports the running destination, separately from the saved selection.

**Save config** alone retains the settings for the next bridge start. It does not change a running connection.

The bridge waits for both directions to become idle before changing the YSF link. The adapter, serial ports and official WIRES-X process stay running during a live apply. Native WIRES-X room selection is independent and remains controlled by WIRES-X.

## Safeguards

- Requests are bound to the exact adapter process, its start time, station root and current owner tag. Stale requests are rejected.
- Applying the already active settings does not unlink or reconnect the reflector.
- DNS resolution is asynchronous. A failed lookup leaves the current destination selected.
- The bridge logs out before joining another room: it stops old-room keepalives, sends three unlink requests spaced 250 ms apart, then allows a settling interval before contacting the new endpoint. This phase is nonblocking and leaves serial servicing running. A local logout-send failure prevents the new join.
- Voice forwarding remains closed during handover until the new reflector has acknowledged and the engine is idle. Old-peer datagrams are discarded rather than admitted after reconnect.
- A new reflector that fails to acknowledge is logged out with the same retry sequence before returning to the previous endpoint. The UI reports failure rather than claiming success. If that cleanup fails or the previous reflector does not acknowledge, forwarding stays closed.
- The switch retains the UDP local port and clears old-room stream state. The next over uses the applied DG-ID policy.
- A continuously busy connection is not forcibly interrupted: the request expires after two minutes and can be retried.
- Changing between IPv4-only and IPv6-only destinations requires a bridge restart. Same-family destination changes support live apply.

An older running adapter needs one initial update/restart to gain this capability. The configuration window refuses to pretend that it can reload an older adapter, and does not restart WIRES-X on its own.

## Reflector connection lists

The bridge sends a YSF unlink to the previous endpoint before joining the next. **Applied** means that the selected new endpoint has acknowledged; the YSF protocol does not provide a separate acknowledgement proving removal of the old server's membership entry.

Reflector dashboards are not necessarily live connection views. For example, pYSF3 version 20240210 publishes its gateway list every 120 seconds, and its web page refreshes every 60 seconds. A short visit to another room may therefore never appear in the list, and the previous room can remain displayed after a successful handover. Other reflectors may use different intervals.

A delayed connection entry alone does not prove duplicate audio. If the same over is heard in both rooms, compare its callsign, time, reported gateway and actual outgoing UDP endpoints. Do not dismiss an audible duplication report as dashboard delay without checking those separately.

## Verification

The build includes actual WinForms button-click and settings/ownership tests, real loopback UDP switch and rollback tests, the production adapter's parsed apply/receive functions, and idle-boundary tests in both voice directions. Existing protocol, metadata, encoded-voice preservation, queue, startup and lifecycle tests remain required. These software tests do not certify subjective audio quality or resolve unrelated native counter/admission defects.
