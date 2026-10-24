# Stage 5 Findings (read-only Mac prototype)

Host setup: `mac/.venv` (python 3.9.6 system python, bleak 1.1.1 + pyobjc 11.1, pinned in `mac/requirements.txt`).
Remove with `rm -rf mac/.venv` and drop the terminal entry in System Settings > Privacy & Security > Bluetooth.
Scripts: `mac/scan.py` (passive), `mac/probe.py` (read-only GETs), `mac/probe2.py` (passive listen + standard battery read). Log: `mac/probe-log.txt` (local only).

Confidence: all items below are **observed on the Mac** (single source) unless noted.

## Results
- [x] Headphones visible to a Mac over BLE while connected to Mac + iOS, phone app closed. Advertised by name `JBL Tune 780NC`; the vendor service UUID is NOT in the advertisement.
- [x] Mac connects over GATT with no pairing prompt (bonding not needed to connect/write). Vendor service `...2e636f6d0000` present with chars `...0002` (write, write-no-response) and `...0001` (notify, read).
- [x] Writing 5 GET frames (tags 0x18, 0x19, 0x1a, 0x0d, 0x04) was accepted, but **no reply and no unsolicited notification** arrived.
- [x] Standard Battery service 0x180F / 0x2A19 is readable and notifies: **50 %** (0x32) at 19:31:56. The phone app never used it in the capture.
- [ ] Why no reply? Hypothesis (capture + code, untested): device ignores GETs until `SET HostType (0x2f) = 01` (code hard-codes 01 for all models). In the capture the device also pushes PairingStatus (0x2e) right after notify enable; the Mac got no such push.
- [ ] Does a second host keep control while the phone app is also connected? Not tested (phone app was closed).

## Battery data points
| Time | Source | Value |
|---|---|---|
| 18:40 | phone app | 48 % |
| 18:11-18:30 | vendor tag 0x0d (capture) | 0x30 = 48 |
| 19:31 | standard 0x2A19 (Mac) | 50 % |
The level went up 48 -> 50, so either it was charged in between or the sources differ. **Need the app % shown right now** to compare. Tag 0x0d stays unverified.

## Open
- [ ] Approval needed: send the single captured frame `00dd0200010005002f00010001` (SET HostType = 01) and retry the GETs.

## Battery update (19:3x, user report)
- iOS Settings > Bluetooth: 50 %. JBL app: 47 %. Standard 0x2A19 read on the Mac: 50 %.
- So the standard battery value matches iOS and is a different number from the app's. The app's figure is 3 points lower than the standard one now, and was 48 % (tag 0x0d = 0x30) at 18:40.
- Prediction to test (not yet confirmed): tag 0x0d currently reads 0x2f (47). If a GET of tag 0x0d returns 0x2f, tag 0x0d = the app's battery % is confirmed from a second point.
- Standard value is usable as a fallback for a menu bar app, but it won't match the JBL app.

## 5d: HostType write (19:37, user approved)
- Sent only `00dd0200010005002f00010001`. Write accepted by the stack, **no reply** within 2.5 s (the capture showed an echo plus ack within ~30 ms). Script stopped, no GETs sent.
- Capture check (hci, phone side): on every LE connect the phone sends `LE Enable Encryption` right away and only then does MTU exchange and GATT traffic (frames 2846, 3311, 6119, 6938, 7862 ...). So the phone's control link is always **encrypted/bonded**.
- Mac link: no pairing prompt appeared, so it is probably unencrypted.
- Hypothesis (capture only for the phone side, Mac side untested): the vendor service silently ignores writes from an unencrypted link.
- [ ] Gate (Stage 5: read battery + ANC state from the Mac): **not passed**. Only standard battery (50 %) works.
- [ ] Options: (a) stop at the standard battery; (b) try to make macOS bond over LE (needs pairing mode, creates a lasting bond; ask first); (c) different transport, e.g. classic RFCOMM ch. 23 (unexamined).

## 5e: RFCOMM channel 23 analysis (capture only, offline)
- Sessions: 18:08, 18:19, 18:21-22, 18:25-29, 18:39, 18:44. Not before every BLE connect: the BLE session at 18:11:25 had no RFCOMM in the 3 min before it (last one 18:08:14).
- Exchange at 18:08:14 (opcodes seen as the first 2 bytes of each message): device sends model ID `42ad54`, firmware string `IoT_SDK_for_BT_Audio_V5.4.0.AB157x`, a 6-byte ID. Then phone and device swap messages `0741`/`0742`/`0740`/`0734` holding the ASCII `in-use` plus 16 to 22 random-looking bytes. Reads as a challenge/response (random data both ways), not as settings commands.
- No setting change appears on RFCOMM at any time. All setting traffic is BLE.
- Code: the string `in-use` is not found as a literal in the Java sources (probably built from bytes or in native code `libcounterfeit`/`libnativelib`, unexamined).
- Two competing explanations for the Mac's silent control channel: (1) unencrypted LE link (see 5d); (2) the device only trusts a host that has completed this RFCOMM challenge on the classic link. Neither is confirmed. The 18:11 BLE session worked 3 min after the last RFCOMM exchange, which is compatible with (2) (one check per classic connection) and with (1).
- Reproducing the challenge would mean working out an authentication algorithm. Not attempted, needs a separate go-ahead.

## 5f: bonding attempt (prep done, waiting for user)
Script: `mac/probe4.py`. User steps: (1) Mac Settings > Bluetooth > forget the headphones (Mac only, iPhone untouched); (2) headphones to pairing mode; (3) report back; (4) user runs the script.
- [ ] Mac forgets headphones
- [ ] Headphones in pairing mode
- [ ] Run probe4 and click Accept on any macOS dialog
- [ ] Result recorded
Undo: Mac Settings > Bluetooth > forget, then pair normally. Mac audio will need re-pairing either way after step 1.
- 5f scan 1 (19:43): not found by name in pairing mode. Wide scan: in pairing mode the headphones advertise no name; a beacon with manufacturer id 6 and bytes `03 01 80 <ADDRESS_PREFIX> ...` at -37 dBm matches the first 3 address bytes (<ADDRESS_PREFIX>) from capture tag 0x0a. Inferred (3 bytes only), not proven. probe4 now matches on that.

## 5f result (19:46, Mac, observed)
- [x] Headphones in pairing mode, Mac forgotten beforehand: connect OK, standard battery 50 %, Fast Pair model ID `42ad54` (= RFCOMM model ID), then the headphones pushed PairingStatus (0x2e=1) on their own, as in the phone capture.
- [x] HostType write: echoed (cmd 3) and acked (`00dd0200010002000000`), same as the phone capture.
- [x] GET replies from the Mac: ANC 0x18 = 7f, Ambient 0x19 = 7f, TalkThru 0x1a = 7f (all off), **battery 0x0d = 0x2f = 47, app showed 47 %**, ProductID 0x04 = 0x215f. All decode with `proto/jbl_proto.py`.
- [x] Battery tag verified with a second point (48 <-> 0x30, 47 <-> 0x2f).
- [x] Stage 5 gate (read battery + ANC state from the Mac): **passed.**
- [ ] Not separated: new LE bond vs pairing mode itself. Retest after normal re-pairing (outside pairing mode).
- [ ] Not tested: Mac and phone app at the same time.
- [ ] Mac audio needs re-pairing for normal use (the Mac forgot the headphones).

## 5g retest (19:53, observed on the Mac)
- Mac audio re-paired normally; the Mac now lists two entries: the audio one ("Headphones") and one the script's pairing dialog created ("Bluetooth device", the LE bond).
- `probe3.py` outside pairing mode: PairingStatus push, HostType echo+ack, all five GETs answered (ANC/AA/TT = 7f, battery 0x0d = 0x2f, ProductID 0x215f). Same as 19:46.
- Conclusion: pairing mode is not needed; a one-time LE pairing was enough. **Whether the bond is strictly required is still unproven** (it was absent in the failing 19:37 run, present in both working runs).
- [ ] Optional: forget only the "Bluetooth device" entry and rerun probe3 to prove the bond is the cause.
- [ ] Not tested: Mac + phone app control at the same time.
- [ ] Stage 5 sign-off by user, then Stage 6 go-ahead.

## 5h bond test (19:56, observed)
- User forgot only the LE-only "Bluetooth Device" entry (the one probe4's dialog created); audio entry "Headphones" kept.
- `probe3.py` result: unchanged, full replies (PairingStatus push, HostType echo+ack, 5 GET replies, battery 0x2f).
- Conclusion: the separate LE entry is NOT required. My earlier "needs a bond" explanation is not supported as stated.
- What differs between failing (19:31, 19:37) and working (19:46, 19:53, 19:56): the Mac's pairing with the headphones was removed and made fresh in between (also the headphones went through pairing mode). Either a stale old Mac pairing blocked the control link, or a fresh pairing gives the Mac LE-usable keys. Not distinguished.
- [ ] Open: if it fails again later, retry order = check Mac pairing state, forget + re-pair headphones on the Mac (pairing mode).
- [ ] Open: Mac + phone app at once, untested.

## Stage 6a (ANC toggle) - prep, user approved 19:5x
Script `mac/probe5.py`: HostType, GET 0x18, SET ANC on (`00dd02000100050018000100ff`, 5x in capture), GET, hold 6 s, SET ANC off (`00dd020001000500180001007f`, 4x in capture), GET 0x18-0x1a. Starting state was all off, so the end state equals the start state.
- [x] Run 19:59:15, result below

### Stage 6a result (observed on the Mac)
- SET ANC on: device pushed a state notification (`...18 00 01 00 ff | 19 00 01 00 7f | 1a 00 01 00 7f`) then the standard ack. GET read back `ff`.
- SET ANC off: state notification all `7f`, ack, and the final GET of 0x18/0x19/0x1a returned all `7f` (= starting state).
- Same sequence as the phone capture (state push first, ack second). Write path from the Mac is confirmed for the ANC tag.
- [ ] User to say whether ANC was audibly heard switching on and off.
- [x] User heard ANC switch on and off (19:5x).

## Stage 6b (Ambient Aware + TalkThru) - prep, user approved
Script `mac/probe6.py`: HostType, GET 0x18-0x1a, SET Ambient Aware (`00dd02000100050019000100ff`, 2x in capture), GET, hold 6 s, SET TalkThru (`00dd0200010005001a000100ff`, 2x in capture), GET, hold 6 s, SET all off (`00dd020001000500180001007f`, always sent at the end, even after an error). Evidence = device state push + read-back, not hearing.
- [x] Run 20:03:37, result below

### Stage 6b result (observed on the Mac)
- Baseline all `7f`. SET Ambient Aware: state push `18=7f 19=ff 1a=7f`, ack, read-back identical.
- SET TalkThru: state push `18=7f 19=7f 1a=ff`, ack, read-back identical. (Setting TalkThru switched Ambient Aware off: exclusive group, as in the capture.)
- SET all off: state push all `7f`, ack, final read all `7f` (= start state).
- Gate 6b: passed. Only captured frames were sent. The log label said "probe5" in this run (copied header text, fixed in the file afterwards); the run was `probe6.py`.
- [ ] Next Stage 6 candidates (user go-ahead needed): Voice Aware level, balance, Spatial Sound, Auto Power Off.

## Stage 6c (full settings suite) - prep, user approved ("run entire suite, auto power off last")
Script `mac/probe7.py`. Reads a baseline of 0x23, 0x15, 0x22, 0x0c40, 0x0c41, 0x12 first, then per group: SET each captured frame, read it back, compare, then restore the baseline; a finally block restores all again. Groups in order: Voice Aware (low/mid/high/off), balance (0/-16/+16/off), Spatial (music/movie/game), voice prompts (off/on), Auto Power Off last (30 min/1 h/2 h/off). Every test frame must be byte-identical to a phone write in the capture, otherwise skipped.
Excluded on purpose: button gestures, EQ, Smart Audio & Video, LE Audio, Auracast, Spatial "off" (capture shows two codes, restored from baseline instead).
- [x] Run 20:12:19, result below

### Stage 6c result (observed on the Mac, 22 steps)
- Baseline: 0x23=03 (Voice Aware off), 0x15=32 (balance off), 0x22=03 (Spatial off), 0x0c40=00 (voice prompts off), 0x0c41=01, 0x12=0807 (Auto Power Off off, stored 30 min).
- PASS (acked, read back identical): Voice Aware low/mid/high/off (81/82/83/03), balance 0/-16/+16/off (b2/a2/c2/32), Spatial music/movie/game (82/81/83), Auto Power Off 30 min/1 h/2 h (0887/108e/209c).
- "MISMATCH" x3, all explained by the device normalising values, not by failed writes:
  - Voice prompts: wrote `ff`/`7f`, read `80`/`00`. Status bit is correct (on=80, off=00); the device drops the level bits (7f -> 0). Baseline (`00`) = prompts were OFF.
  - Auto Power Off "off": wrote `201c` (2 h, off), read `0807` (30 min, off). The device keeps/uses its default 30 min as the stored duration when switched off. Baseline `0807` = off at 30 min.
- Restores: every group restored and verified; final read of all six tags == baseline.
- Gate Stage 6: passed for all tested settings. Spatial mode numbers (music=82, movie=81, game=83) are now confirmed by device read-back (though not by listening).
- [ ] Settings are currently at the end-of-capture state, not necessarily the user's original: voice prompts OFF (likely originally ON, English), Auto Power Off OFF (likely originally 30 min ON). Offer to set these back with captured frames (`00dd020001000a00400c0100ff410c010001`, `00dd020001000600120002000887`).
