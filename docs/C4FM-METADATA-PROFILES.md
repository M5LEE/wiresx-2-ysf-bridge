# C4FM metadata format

WiresX 2 YSF Bridge forwards supported native caller information into YSF V/D2 frames. Alpha.9 corrects the metadata cycles used for C4FM callsign display while retaining the existing voice payload and packet cadence.

## Frame profiles

The optional native data record determines the transmitted cycle:

| Optional record | FT | Frame numbers | Optional data slots |
|---|---|---|---|
| Absent, unsupported or invalid | 5 | FN0–FN5 | None |
| Supported valid 7-byte record | 6 | FN0–FN6 | DT1 |
| Supported valid 20-byte record | 7 | FN0–FN7 | DT1 and DT2 |

The same FT value is used in the opening header, communication frames and closing terminator. Short records are padded within DT1, without advertising a second data slot. The bridge uses the standard CS=10 value.

## Identity fields

| Frame | Contents |
|---|---|
| FN0 | Destination |
| FN1 | Source callsign |
| FN2 | Bridge downlink callsign |
| FN3 | Native uplink callsign |
| FN4 | Native Rem1 and Rem2 |
| FN5 | Native Rem3 and Rem4 |

Headers and periodic metadata use a consistent bridge downlink. Native uplink and ID/remarks fields are retained. Missing sender models, radio IDs and positions are not fabricated.

## Validation and transmission boundaries

Supported optional records are checked for format, type, end marker and additive checksum. Unsupported or invalid optional data selects the no-data profile without changing the mandatory metadata checks or acknowledgements.

Caller identity, remarks, data and FT are fixed for each transmission. Stop, expiry, caller changes and room changes clear the relevant state so one transmission's profile cannot leak into another. Binary records retain their original bytes, including NUL and high-bit values.

## Tests and reference

`tests/CallsignMetadataTests.cs` and `tests/C4fmProfileTests.cs` cover callsign layout, all supported profiles and envelopes, invalid records, immutable per-transmission state, header/terminator consistency and unchanged voice payloads. See [compatibility and testing](VERIFICATION.md) for release validation and receiver limitations.

Format reference: Yaesu, *C4FM Digital Communication Standard*, callsign data and V/D2 tables, pages 16 and 21: <https://connect.yaesu.com/indivisual/wp-content/uploads/2024/12/C4FM_digital.pdf>.
