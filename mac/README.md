# mac/

Small Python scripts that talk to a JBL Tune 780NC from a Mac using `bleak`. Set up a throwaway environment inside this folder, nothing global:

    python3 -m venv mac/.venv
    mac/.venv/bin/pip install --only-binary :all: -r mac/requirements.txt

macOS asks whether your terminal may use Bluetooth. Allow it. To remove everything: delete `mac/.venv` and the terminal entry in System Settings > Privacy & Security > Bluetooth.

| Script | What it does | Writes to the headphones? |
|---|---|---|
| `scan.py`, `scan_all.py` | passive scan | no |
| `probe.py`, `probe2.py` | connect and read | no (probe.py sends read requests only) |
| `probe3.py` | connect, send one captured "hello" frame (HostType), then read | **one frame**, needs `--i-understand` |
| `probe4.py` | connect while the headphones are in pairing mode (triggers the macOS pairing dialog), then as probe3 | **one frame** (HostType), needs `--i-understand` |
| `probe5.py` | ANC on then off | **yes** |
| `probe6.py` | Ambient Aware, TalkThru, then all off | **yes** |
| `probe7.py` | Voice Aware, balance, Spatial, voice prompts, Auto Power Off, restoring your baseline | **yes** |
| `probe8.py` | direct power off (one captured frame, sent once, needs `--i-understand --power-off --now`, 5 second countdown) | **yes, switches the headphones off** |

`probe5.py` to `probe7.py` change real settings. They only send frames seen in a real capture, restore the baseline, and (like probe3 and probe4) refuse to run without `--i-understand`. They have been run on one unit only. Not for factory reset, firmware update, LE Audio, Auracast, Smart Audio & Video or EQ: the encoder in `proto/` blocks those.

Local values (device address prefix for the pairing-mode beacon, private capture table path) go in `local.config.json` at the repo root, which is gitignored. Copy `local.config.example.json` to start.
