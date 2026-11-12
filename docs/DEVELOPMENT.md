# Building from source

These instructions build WiresX 2 YSF Bridge and its Windows installer. To install a release instead, see the [user guide](../README.md).

## Build requirements

- Windows x64 with .NET Framework 4.8 and the Framework C# compiler at `Microsoft.NET\Framework64\v4.0.30319\csc.exe` under the Windows directory.
- Windows PowerShell 5.1.
- NSIS 3 to create the installer.

The supplied artwork is ready to use. Python and Pillow are needed only to regenerate it with `tools/make_icons.py`.

## Compile and test

Run from the repository root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build.ps1
```

The build compiles the application and libraries with warnings treated as errors, copies runtime scripts and dependencies into `bin`, and generates `bin\artifact-hashes.json` from the compiled assemblies. Tests are enabled by default; their executables are written to `tests\bin`.

The build runs the automated suites included in the selected source snapshot. These use isolated fixtures for device and startup actions; they do not replace tests on a real station.

## Create the installer

After a successful build:

```powershell
New-Item -ItemType Directory -Force .\dist
makensis .\installer\installer.nsi
```

NSIS writes the versioned Setup EXE to `dist`. Original code is MIT-licensed; the bundled com0com dependency retains its own licence and accompanying source. See [third-party notices](../THIRD_PARTY_NOTICES.md).

## Source layout

| Location | Contents |
|---|---|
| `src` | Protocol libraries, WinForms application and PowerShell runtime/setup scripts |
| `tests` | Automated regression and integration tests |
| `installer` | NSIS installer definition |
| `assets` | Application, settings and installer artwork |
| `vendor/com0com` | Virtual-port dependency, licence and upstream source |

See [C4FM metadata format](https://github.com/M5LEE/wiresx-2-ysf-bridge/blob/main/docs/C4FM-METADATA-PROFILES.md) for protocol details and [compatibility and testing](VERIFICATION.md) for release coverage.
