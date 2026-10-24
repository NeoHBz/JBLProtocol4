# Stage 1 Capture Script (JBL Tune 780NC)

Phone: an Android phone (Android 15), adb id `<ADB_ID>`. App: JBL Headphones 5.37.10 (matches decompiled version).
Phone and Mac clocks agree (checked before the capture). Use the phone clock for timestamps.

## Progress notes (updated 2026-10-24 ~18:41)
- Not done / partial: B3, B4 (not logged), C2, C3, D7, E1-E3 (button options tested via app, see action-log), E4 (headset presses logged, effects of single/double/triple not stated), F3 (EQ presets done, **custom band deferred**), F4 spatial, F5 auto power off, G1 restore, G2-G5 finish.
- Deviations: A5 force-stop and B1 idle baseline were not done as written; first ANC change was logged approximately (~18:12:39). Smart Audio & Video drops the connection on every change. LE Audio toggle reboots and re-pairs. Control screen Reset tapped at 18:21:14 (control settings only, by app text).
- Still unrestored: Smart Audio & Video (off since 18:22:18), EQ (off since 18:34:59), original states unknown.

## Update 2026-10-24 ~19:00
- Bug report pulled (`captures/bugreport.zip`), logcat stopped. Analysis in `notes/stage1-findings.md`.
- Still open: G1 restores (originals unknown), G4 turn HCI snoop log off, custom EQ (F3 part), D7, C2/C3, B3/B4.

## Rules
- One action per step. Wait about 5 seconds after each action before the next.
- Write the time (HH:MM:SS) the moment you do the action. Log in `captures/action-log.csv`: `time,step,action,result_seen_in_app`.
- **Never tap:** firmware update, factory reset, "reset" of any kind, OTA prompts. If the app offers an update, dismiss it.
- Skip any feature the app does not show for the Tune 780NC. Write "not shown" in the log. Do not guess.
- Keep other Bluetooth devices off so the capture stays clean.

## A. Setup
- [x] A1. Phone: Settings > About phone > tap Build number 7 times (enables Developer options).
- [x] A2. Settings > System > Developer options > **Enable Bluetooth HCI snoop log** > choose **Enabled** (not "Enabled Filtered").
- [x] A3. Turn Bluetooth **off then on** so the log starts fresh.
- [x] A4. Connect the Tune 780NC to the phone. Open the JBL Headphones app until it shows the headphone's home screen.
- [x] A5. Force-stop the JBL app (long-press icon > App info > Force stop). The app's connection handshake must be in the capture, so it must start after logging began. Keep headphones connected.
- [x] A6. Mac terminal, start the app log (kept running in a second terminal until the end):
  `adb -s <ADB_ID> logcat -v time > captures/logcat.txt`
- [x] A7. Create the action log: `echo "time,step,action,result_seen_in_app" > captures/action-log.csv`

## B. Baseline and connection
- [x] B1. Log the time. Do nothing for 60 seconds (idle baseline).
- [x] B2. Log the time. Open the JBL app (this captures the handshake and first reads).
- [ ] B3. Wait 30 seconds on the home screen without touching anything. Note battery % shown.
- [ ] B4. Close the app (swipe away). Wait 15 seconds. Reopen it. (Reconnect pattern.)

## C. Battery
- [x] C1. Note the battery % shown in the app, and the Android Bluetooth battery %.
- [ ] C2. Put the headphones on the charger for 1 minute, then unplug. Note any change in the app. (Charging state.)
- [ ] C3. Come back to the app after 10 minutes of use and note the new %. (Optional, gives a second data point.)

## D. Noise control (one change per step, note the mode shown)
- [x] D1. Set to **ANC on** in the app.
- [x] D2. Set to **Ambient Aware** in the app.
- [x] D3. Set to **Off** in the app.
- [x] D4. Set to **ANC on** again (repeat for a second sample).
- [x] D5. Set to **Off** again.
- [x] D6. If the app shows **TalkThru**, enable then disable it.
- [ ] D7. If the app shows an ANC strength or adaptive option, toggle it.
- [x] D8. **On the headphones:** press the ANC button once. Note the resulting mode (voice prompt or app change). Repeat twice more to see the cycle.
- [x] D9. **On the headphones:** double press the ANC button. Note the result.

## E. Buttons (only options the app shows)
- [x] E1. Open the button settings. Log which buttons and gestures are listed.
- [x] E2. For the first gesture, switch through each assignable option in turn, one step per option. Log the option names.
- [x] E3. Put the gesture back to its original option. Repeat E2/E3 for each remaining gesture.
- [x] E4. Physically press each gesture once on the headphones. Log what happens.

## F. Toggles and sliders (only if shown)
- [x] F1. Voice Aware: on, then off, then slider to minimum, then to maximum.
- [x] F2. Left/right balance: on, then off, then slider fully left, then fully right, then center.
- [ ] F3. Equalizer: switch through each preset one by one. Then change one custom band to its minimum, then maximum, then reset the band.
- [x] F4. Spatial Sound (if present): off, then each mode in turn.
- [x] F5. Auto power off (if present): each option in turn, ending on the original.
- [x] F6. Smart Audio & Video, Auracast, LE Audio (if present): on, then off. **If a toggle reconnects the headphones, stop and log it.**
- [x] F7. Any other setting the app shows (language, voice prompts, sidetone, find my headphones): toggle once and log the name.

## G. Finish
- [ ] G1. Put every setting back to what you wrote down before you started.
- [x] G2. Stop logcat (Ctrl+C in that terminal).
- [x] G3. Pull the snoop log. Android 15 on a non-rooted phone hides the raw file, so use a bug report:
  `adb -s <ADB_ID> bugreport captures/bugreport.zip`
  The log is inside the zip at `FS/data/misc/bluetooth/logs/btsnoop_hci.log` (extract it in the container).
- [ ] G4. Turn off the HCI snoop log in Developer options when done (logs hold your Bluetooth traffic).
- [x] G5. Log the start time of B1, plus the name of the headphones as it appears in the app.

## Files expected in `captures/`
- `bugreport.zip` (contains the btsnoop log)
- `logcat.txt`
- `action-log.csv`

## Privacy
The bug report and logcat contain device identifiers, app names, and possibly account info. They stay in the project folder on your Mac. Do not share or upload them.

## Success criteria (Stage 1)
Pass if the capture shows which bytes change for ANC on/off and for battery, and the transport (BLE GATT vs RFCOMM). If not, stop and re-plan.
