# Stage 0 Recon

Confidence tags: **code** = seen in decompiled code only (single source, unverified). Nothing is "observed in capture" yet.

## Checklist
- [x] Build container, verify tools (jadx 1.5.1, apktool 2.7.0, tshark 4.2.2, java 17, python 3.12, bun 1.4.4)
- [x] Unpack `.apkm` bundle into `decompiled/apkm/`
- [x] Decompile base.apk (jadx -> `decompiled/jadx/`, apktool -> `decompiled/apktool/`)
- [x] Record package, version, permissions, native libs, obfuscation
- [x] Prior-art search (limited, 2 searches)
- [x] Classify features
- [x] Resolve device ambiguity: user confirmed **JBL Tune 780NC** (not Tour One M2, not Live 780NC)
- [ ] Stage 0 gate sign-off by user

## Device (resolved)
User confirmed the Bluetooth name: **JBL Tune 780NC** (`hm/e.java:198`, constant `a2`).
- Tour One M2 (`hm/e.java:546`) and Live 780NC (`hm/e.java:175`) are different products. Ignore them.
- In `cn/o0.java:728` the app groups Tune 780NC with Tune 770NC, 775NC and 777NC (shared device image map, and the pairing screen reuses `welcome_tune_770nc` assets). **Code only:** the 780NC likely shares a command set with the 770NC family.
- Consequence: the handoff feature list was written for a different mental model. Auracast, Smart Audio & Video, Spatial Sound modes and TalkThru may not exist on the Tune 780NC. Stage 1 will test each one on the real device, and anything the app does not show is dropped.
- Which Harman command classes the Tune 780NC enables is still unconfirmed. It needs a code path trace in Stage 2.

## APK
- Package: `jbl.stc.com`
- Version: 5.37.10, versionCode 260825178 (source `.apkm`, APKMirror, posted 2026-09-01)
- Bundle: base.apk plus split config APKs (arm64, armv7, x86, densities)
- Permissions of interest: BLUETOOTH, BLUETOOTH_ADMIN, BLUETOOTH_SCAN, BLUETOOTH_CONNECT, ACCESS_FINE/COARSE_LOCATION, INTERNET, RECORD_AUDIO, CAMERA
- Features: bluetooth + bluetooth_le both required

## Native libs (arm64-v8a)
`libDspConfig`, `libamazonjniutil`, `libc++_shared`, `libcalibrationLib`, `libcounterfeit`, `libdatastore_shared_counter`, `libnative-anc-1568`, `libnative-anc`, `libnative-peq-serialize`, `libnative-peq`, `libnativelib`, `libpersonifiAlgorithm`, `libsbcconverter`

- Audio/DSP: ANC filters, PEQ, EQ calibration, SBC, PersonifAI hearing.
- Unclear: `libnativelib` (loaded by `com/harman/impcmdcommon/ImpCmdCommonUtil.java:11`) and `libcounterfeit` (likely a fake-device check). These need a look in Stage 2, since either could touch framing or auth.
- No protocol framing found in native code so far.

## Obfuscation
- Mixed. About 18k Java files, ~11.5k classes. Vendor/third-party packages are renamed to short letters (R8).
- App code keeps real names: `jbl.stc.com.*`, `jblcontroller.*`, `com.harman.bluetooth.*` (145 files), `com.airoha.*` (1127 files).
- Command classes are readable: `com/harman/bluetooth/imp/cmd/`.
- Transport classes: `SppDevice.java` (RFCOMM) and `BleDevice.java` (GATT) in `com/harman/bluetooth/imp/mgr/`, plus `BesDeviceConnector.java` (Bestechnic chip naming).
- Only crypto in the Harman layer: AES and SHA256 under `com/harman/bluetooth/ota/spp/utils/sha/` (firmware OTA, off limits). Command traffic shows no encryption in code. **Unverified until capture.**
- Jadx finished with 32 errors in methods. Failed methods may matter later.

## Early protocol hints (code only, unverified)
- Frame looks like `AA <cmd> <len> <payload>`. Example: `BatteryInfoCmd` request is `AA 25 00`, response header `aa25` (`com/harman/bluetooth/imp/cmd/BatteryInfoCmd.java`).
- Response has left/right charge status and per-side battery level. Whether it is exact percent is not confirmed.
- Checksum/CRC: not yet found.
- Airoha libs (`com/airoha/liblinker`, RACE-style) are present too. They may serve other models. Do not assume the 780NC uses them.

## Prior art (2 searches only)
- No public JBL/Harman app-protocol RE project found.
- Analogues, useful as method only: Plutoberth/SonyHeadphonesClient (Sony), LibrePods (AirPods), a Jabra Elite 10 GATT write-up.
- CERT VDE-2024-076 / HBSA-2025-0001: unauthenticated GATT control on JBL Live Pro 2 TWS and Tune Flex. Suggests Harman devices can accept commands without auth. **Different models, not proof for the 780NC.**
- Airoha RACE (Troopers 2025, Insinuator): can read/write flash and RAM. If any Airoha path exists, that is Off Limits.
- Not yet searched: GitHub code search for the `AA 25` frame, "harman" + "bes" + "spp". Worth one more pass.

## Feature classification
Class names come from `com/harman/bluetooth/imp/cmd/`. A class name existing is not proof the 780NC supports it.

| Feature | Class | Evidence |
|---|---|---|
| Battery (exact) | protocol-controllable | `BatteryInfoCmd` (code) |
| ANC / Ambient Aware / Off | protocol-controllable | `AdvancedAncCmd` (code) |
| TalkThru | uncertain | not yet mapped to a command |
| ANC button cycle / double press | uncertain | firmware-side behavior, likely config via `GestureCmd` |
| Multi-function button mapping | protocol-controllable | `GestureCmd` (code) |
| Call control | OS-level | standard HFP, informational |
| Smart Audio & Video | uncertain | no matching class name yet |
| Auracast | uncertain, **low Mac value** | macOS has no Auracast support |
| LE Audio | protocol-controllable, **low Mac value** | `LeaAudioCmd`; macOS LE Audio support is limited |
| Equalizer | protocol-controllable | `SegmentEQCmd`, `LowEQCompensationCmd`; PEQ math in native libs |
| Spatial Sound | protocol-controllable | `SpatialStatus3DCmd`; spatial rendering itself is on-device or OS |
| Left/Right balance | protocol-controllable | `LeftRightSoundBalanceCmd` |
| Voice Aware | protocol-controllable | `VoiceAwareCmd` |
| Auto Power Off | uncertain | no matching class name yet |
| Cloud-dependent | n/a | Firebase, AWS analytics, ads present. None of the listed features look cloud-bound yet. |

## Stage 0 gate
Protocol logic is in readable Java, not in native code, and no command-level encryption was found. **Gate: provisionally passed.** One caveat left: `libnativelib` / `libcounterfeit` unchecked.

## Next
1. You give the go-ahead for Stage 1 (I write `notes/capture-script.md`, scoped to the Tune 780NC).
