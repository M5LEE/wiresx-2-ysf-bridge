# Native auxiliary data

This experimental source variant preserves supported optional native metadata records when constructing YSF data-channel blocks. It is not the recommended installation release; use the [release downloads](https://github.com/M5LEE/wiresx-2-ysf-bridge/releases) for the current application.

## Record handling

Supported records are checked for their hexadecimal encoding, type, terminator and checksum. Binary record bytes are retained, including NUL and high-bit values, and are associated with the caller and transmission that supplied them. Stop, expiry and room boundaries clear the relevant transmission state.

## Limitations

This variant uses a fixed FT7 cycle. Preserving record bytes alone does not establish complete C4FM profile compatibility or correct receiver display. It is not suitable as a replacement for the current release's complete-profile implementation. Voice transport, acknowledgement rules and safety checks remain separate from optional metadata validation.
