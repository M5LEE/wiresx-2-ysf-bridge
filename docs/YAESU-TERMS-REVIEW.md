# WIRES-X terms and distribution review

Reviewed 13 November 2026 against bridge source commit `3325123e2d4c3ae44660b96a0a4b5007599e28fd`.

## Result

The installer EULA contains no express restriction naming virtual COM ports, radio-profile emulation or YSF bridging. This is not affirmative permission for this operating arrangement. The server agreement preserved in search-index text leaves a material question about use outside Yaesu's intended purposes and continued server access. Neither the bridge's MIT licence nor its independence notice resolves that question.

This is a technical and documentary review, not a legal opinion or a statement of Yaesu approval. The particular server terms accepted by the operator, any later account notices and the development history were not available for verification.

## Exact software checked

The official [HRI-200 download page](https://www.yaesu.com/product-detail.aspx?CatName=WIRESInternetLinking&Model=HRI-200) links to [WIRES-X PC Software 2.010](https://www.yaesu.com/Files/BB2A96CD-1018-01AF-FAAE1B090D458A7B/wx2010en.zip). Its `wx2010en/en-US/WiresSetup.msi` contains the complete installer EULA, headed WIRES END-USER LICENSE AGREEMENT. The generic heading does not mean that a WIRES-II agreement was substituted: the text was extracted from this WIRES-X installer.

The MSI product version is `2.0.10`. The embedded `WIRES_X.EXE` reports file and product version `2.0.1.0`; its hash exactly matches the bridge's supported-executable pin. The archive, MSI, embedded licence text and PE version resource were inspected without installing or running the Yaesu software or accepting its agreement.

| Evidence | SHA-256 |
|---|---|
| Official `wx2010en.zip` | `b07acf93614f60bd306bc3f904642072e303265e14aa0b0456836da1a28de78c` |
| `WiresSetup.msi` | `41390cb4be449020043cfb8da029904db2740d869d65a214f908c30823de3ede` |
| Complete extracted EULA RTF | `d59b8b971bba330895a118045edceee54c280c377527fb45c4484b987d40925d` |
| Embedded WIRES-X executable | `8f05dc26794144438566b880ce775f5178d62eb3c4deb8c053089216342bc671` |

The vendor's proprietary installer, executables and full EULA are not redistributed by this review.

## Relevant terms

The software EULA covers both the program and associated Internet services. It restricts reverse engineering, decompilation and disassembly, with an express exception for activity permitted by applicable law despite the restriction. It limits installation/copying and transfer, preserves proprietary notices, makes the operator responsible for other service users, and allows service disablement for abuse or legal/rule violations. It also contains an indemnity and selects California/US law and California courts. No specific requirement to keep an attached physical radio powered on was found.

The [WIRES-X server agreement preserved in search-index text](https://www.yaesu.com/jp/en/wires-x/regist/registration.php?id=d315b4dcb3) requires compliance with Yaesu's rules and reserves refusal of access for software/HRI-200 modification, unintended use, illegal access, disruption or loss of eligibility. It also specifies California courts. The complete text was available in a search index, but the live registration URL returned HTTP 404 during this review. Its current applicability to a particular account cannot therefore be certified; an account-specific or newer agreement could change the assessment.

## Assessment of the three features

| Feature and observed implementation | Assessment |
|---|---|
| **Virtual-port redirection.** `BridgeSupervisor.ps1` changes Windows device friendly names so WIRES-X selects a virtual serial endpoint. The bridge forwards traffic to the genuine HRI-200. | No specifically named prohibition was found. The observed action changes Windows device presentation; it does not establish that the Yaesu executable or HRI firmware is modified. Whether Yaesu treats this arrangement as unintended server use remains unresolved. |
| **Radio-profile emulation.** `voice-adapter.ps1` uses locally captured FTM-100 metadata responses when the radio is off, while forwarding live HRI identity/handshake replies. | No specifically named prohibition was found. The way the profile and implementation were developed still matters under the reverse-engineering clause and applicable exceptions. Owning the hardware alone does not settle every contractual or copyright issue. |
| **Bridging to YSF.** The existing WIRES-X client performs its normal login and the bridge exchanges encoded voice/data with the YSF side. | No express cross-network ban was found. Yaesu's intended-use provision and responsibility for service users are the material contractual concerns. This review does not establish an entitlement to connect the two services or prevent Yaesu refusing access. |

The observer reads a native Windows Edit control through window messages. No executable patching, process-memory read/write API or injected code was found in the reviewed observer implementation. This bounded source inspection does not prove how every earlier development artefact was produced or how an uninspected binary behaves.

## Legal limits

For a lawful UK user, [CDPA section 50BA](https://www.legislation.gov.uk/ukpga/1988/48/section/50BA) permits qualifying observation, study and testing to discover underlying ideas and principles. [Section 50B](https://www.legislation.gov.uk/ukpga/1988/48/section/50B) has narrower conditions for decompilation needed for interoperability; [section 296A](https://www.legislation.gov.uk/ukpga/1988/48/section/296A) limits conflicting contractual restrictions on specified permitted acts. These provisions do not automatically confer access to Yaesu's servers or clear all uses of captured material. The EULA's foreign-law provisions also require care before treating UK exceptions as a complete answer.

Copyright permission, compliance with a contract and continued access to a privately operated service are separate questions. Written confirmation from Yaesu could establish whether it approves this operating arrangement. Appropriate legal advice could assess the copyright and contractual position without assuming that approval. No request has been sent to Yaesu and no agreement has been accepted on the operator's behalf.

## com0com and notices

The retained com0com 3.0.0.0 upstream source archive contains the driver and management-tool sources, build instructions and copyright/licence headers. It is the matching-version source package identified in [ORIGIN.md](../vendor/com0com/ORIGIN.md), not a new binary-reproducibility certification. Keep the archive, GPL text, upstream readme, origin record and hashes with the separately bundled component. The original bridge code remains under MIT, and the [Yaesu independence notice](../THIRD_PARTY_NOTICES.md) remains applicable.

[The distribution check](../tools/Assert-DistributionNotices.ps1) requires these retained files, verifies the upstream licence/readme/source hashes and checks the two licensing/independence disclosures. The build runs it before compilation and against the staged payload, including when tests are skipped. The installer lists the com0com files explicitly, so a missing listed file stops installer compilation. See [building instructions](DEVELOPMENT.md) for checking an extracted release before publication. These checks protect packaging; they do not grant vendor permission or establish the provenance of unrelated code.

Validation for this change: 17 isolated guard cases passed under PowerShell 7.7 on Linux, covering complete payloads, absent/empty/corrupt retained files, invalid hash entries, removed disclosures, acceptable notice rewording and enforcement with `-SkipTests`. The build and guard scripts parsed successfully. A Windows PowerShell 5.1/.NET build and an NSIS installer build were not performed in this environment. The previously identified alpha.9 release page returned 404 when checked, so that published binary was not inspected.
