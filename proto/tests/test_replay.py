"""Replay every frame captured from the phone and the headphones (proto/fixtures/gatt.tsv)."""
import os
import sys

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import jbl_proto as p  # noqa: E402

_FIX = os.path.join(os.path.dirname(__file__), "..", "fixtures")
FIXTURE = os.environ.get("JBL_FIXTURE") or next(
    (f for f in (os.path.join(_FIX, "gatt.tsv"), os.path.join(_FIX, "gatt.public.tsv")) if os.path.exists(f)),
    os.path.join(_FIX, "gatt.tsv"))
ACK = bytes.fromhex("00dd0200010002000000")

if not os.path.exists(FIXTURE):
    pytest.skip("no capture fixture found; supply your own (see README)", allow_module_level=True)


def load():
    """Frames on the command characteristics: handle 0xb003 = phone writes, 0xb005 = device notifications."""
    out = []
    for line in open(FIXTURE):
        r = line.rstrip("\n").split("\t")
        if len(r) > 5 and r[4] in ("0xb003", "0xb005") and r[5]:
            out.append((r[1], "APP" if r[4] == "0xb003" else "DEV", bytes.fromhex(r[5])))
    return out


FRAMES = load()
APP = [f for f in FRAMES if f[1] == "APP"]
DEV = [f for f in FRAMES if f[1] == "DEV"]


def test_fixture_size():
    assert len(FRAMES) == 659
    assert len(APP) == 245


def test_every_frame_parses_and_reencodes_byte_for_byte():
    bad = []
    for ts, d, raw in FRAMES:
        try:
            fr = p.parse_frame(raw)
            if fr.encode() != raw:
                bad.append((ts, d, raw.hex()[:40]))
        except ValueError as e:
            bad.append((ts, d, str(e)))
    assert not bad, bad[:5]


def test_tlv_roundtrip_single_packet_frames():
    checked = skipped = 0
    for ts, d, raw in FRAMES:
        fr = p.parse_frame(raw)
        if fr.count != 1:
            skipped += 1
            continue
        if d == "APP" and fr.command == p.CMD_SET:
            assert p.encode_tlvs(p.parse_tlvs(fr.payload)) == fr.payload, (ts, raw.hex())
        elif d == "DEV" and fr.command in (p.CMD_GET, p.CMD_NOTIFY_APP, p.CMD_SET):
            status, tlvs = p.parse_status_tlvs(fr.payload)
            assert status == 0
            assert p.encode_status_tlvs(status, tlvs) == fr.payload, (ts, raw.hex())
        else:
            continue
        checked += 1
    print(f"\nTLV round trip: {checked} frames, {skipped} multi-packet skipped")
    assert checked == 542


def test_every_device_ack_is_the_same_ack():
    acks = [raw for _, d, raw in DEV if p.parse_frame(raw).command == p.CMD_SET]
    assert acks and all(a == ACK for a in acks)


def test_get_frames_rebuild():
    n = 0
    for ts, d, raw in APP:
        fr = p.parse_frame(raw)
        if fr.command == p.CMD_GET:
            tags = [int.from_bytes(fr.payload[i:i + 2], "little") for i in range(0, len(fr.payload), 2)]
            assert p.build_get(tags, identifier=fr.identifier) == raw, (ts, raw.hex())
            n += 1
    print(f"\nGET frames rebuilt: {n}")
    assert n > 20


def known_set_frames():
    for ts, d, raw in APP:
        fr = p.parse_frame(raw)
        if fr.command == p.CMD_SET and fr.count == 1:
            tlvs = p.parse_tlvs(fr.payload)
            if tlvs and all(t in p.FEATURES for t, _ in tlvs):
                yield ts, raw, fr, tlvs


def test_every_known_set_frame_is_reproduced_by_the_encoder():
    n = 0
    tags_seen = set()
    for ts, raw, fr, tlvs in known_set_frames():
        rebuilt = []
        for tag, value in tlvs:
            name, args = p.decode_feature(tag, value)
            rebuilt.append(p.encode_feature(name, **args))
        assert rebuilt == tlvs, (ts, raw.hex())
        assert p.build_set(rebuilt, identifier=fr.identifier) == raw, (ts, raw.hex())
        tags_seen.update(t for t, _ in tlvs)
        n += 1
    print(f"\nknown SET frames reproduced: {n}; tags: {sorted(hex(t) for t in tags_seen)}")
    assert n == 75
    for t in (p.TAG_ANC, p.TAG_AMBIENT, p.TAG_TALKTHRU, p.TAG_VOICE_AWARE, p.TAG_BALANCE, p.TAG_SPATIAL,
              p.TAG_AUTO_OFF, p.TAG_VOICE_PROMPT, p.TAG_BTN_MFB_SINGLE, p.TAG_BTN_MFB_DOUBLE,
              p.TAG_BTN_MFB_TRIPLE, p.TAG_BTN_MFB_HOLD, p.TAG_BTN_ANC_SINGLE, p.TAG_HEARTBEAT):
        assert t in tags_seen, hex(t)


def test_high_level_builders_match_captured_bytes():
    cases = [
        (p.set_anc(True), "00dd02000100050018000100ff"),
        (p.set_all_noise_off(), "00dd020001000500180001007f"),
        (p.set_ambient_aware(), "00dd02000100050019000100ff"),
        (p.set_talkthru(), "00dd0200010005001a000100ff"),
        (p.set_voice_aware(3), "00dd0200010005002300010083"),
        (p.set_voice_aware(1), "00dd0200010005002300010081"),
        (p.set_voice_aware(2), "00dd0200010005002300010082"),
        (p.set_voice_aware(3, on=False), "00dd0200010005002300010003"),
        (p.set_balance(0), "00dd02000100050015000100b2"),
        (p.set_balance(-16), "00dd02000100050015000100a2"),
        (p.set_balance(16), "00dd02000100050015000100c2"),
        (p.set_balance(0, on=False), "00dd0200010005001500010032"),
        (p.set_spatial("music"), "00dd0200010005002200010082"),
        (p.set_spatial("movie"), "00dd0200010005002200010081"),
        (p.set_spatial("game"), "00dd0200010005002200010083"),
        (p.set_auto_power_off(1800), "00dd020001000600120002000887"),
        (p.set_auto_power_off(3600), "00dd02000100060012000200108e"),
        (p.set_auto_power_off(7200), "00dd02000100060012000200209c"),
        (p.set_auto_power_off(7200, on=False), "00dd02000100060012000200201c"),
        (p.set_voice_prompt(True), "00dd020001000a00400c0100ff410c010001"),
        (p.set_voice_prompt(False), "00dd020001000a00400c01007f410c010001"),
        (p.set_gesture("btn_mfb_single", p.G_EQ_ONOFF), "00dd020001000500820f0100c8"),
        (p.build_heartbeat(), "00dd02000100040002000000"),
    ]
    captured = {raw for _, _, raw in APP}
    for built, hexstr in cases:
        assert built.hex() == hexstr
        assert built in captured, hexstr


def test_device_notification_echoes_what_was_set():
    """After each known single-tag SET, a notification within the next replies carries the same tag and value."""
    checked = mismatches = 0
    for i, (ts, d, raw) in enumerate(FRAMES):
        if d != "APP":
            continue
        fr = p.parse_frame(raw)
        if fr.command != p.CMD_SET or fr.count != 1:
            continue
        tlvs = p.parse_tlvs(fr.payload)
        if len(tlvs) != 1 or tlvs[0][0] not in p.FEATURES or tlvs[0][0] == p.TAG_HEARTBEAT:
            continue
        seen = set()
        for _, d2, raw2 in FRAMES[i + 1:i + 6]:
            if d2 == "DEV":
                f2 = p.parse_frame(raw2)
                if f2.command == p.CMD_NOTIFY_APP and f2.count == 1:
                    seen.update(p.parse_status_tlvs(f2.payload)[1])
        checked += 1
        if tlvs[0] not in seen:
            mismatches += 1
    print(f"\nSET echoed by device: {checked - mismatches}/{checked}")
    assert checked > 50
    assert mismatches <= checked * 0.1


def test_noise_modes_are_an_exclusive_group_in_replies():
    n = 0
    for _, d, raw in DEV:
        fr = p.parse_frame(raw)
        if fr.command != p.CMD_NOTIFY_APP or fr.count != 1:
            continue
        tl = dict(p.parse_status_tlvs(fr.payload)[1])
        if p.TAG_ANC in tl and p.TAG_AMBIENT in tl and p.TAG_TALKTHRU in tl:
            on = [t for t in (p.TAG_ANC, p.TAG_AMBIENT, p.TAG_TALKTHRU) if p.decode_sl1(tl[t])[0]]
            assert len(on) <= 1
            n += 1
    assert n >= 8


def test_off_limits_are_refused():
    with pytest.raises(PermissionError):
        p.build_set([(0x000F, b"")])               # FactoryReset
    with pytest.raises(PermissionError):
        p.build_set([(0x0BA0, b"\xff")])           # LE Audio
    with pytest.raises(PermissionError):
        p.build_set([(0x100F, b"\x00" * 8)])       # Smart Audio & Video
    with pytest.raises(PermissionError):
        p.build_set([(0x1234, b"\x01")])           # unknown tag
    for cmd in (0x00FF, 0x0101, 0x0102, 0x0103, 0x0104, 0x02FF):
        with pytest.raises(PermissionError):
            p.build_frame(cmd, b"")


def test_codec_ranges():
    with pytest.raises(ValueError):
        p.set_balance(17)
    with pytest.raises(ValueError):
        p.set_voice_aware(4)
    assert p.decode_sl1(bytes([0xFF])) == (1, 0x7F)
    assert p.decode_sl2(bytes([0x08, 0x87])) == (1, 1800)


def test_battery_candidate_is_decodable_but_unverified():
    levels = set()
    for _, d, raw in DEV:
        fr = p.parse_frame(raw)
        if fr.command in (p.CMD_GET, p.CMD_NOTIFY_APP) and fr.count == 1 and len(fr.payload) > 2:
            for tag, v in p.parse_status_tlvs(fr.payload)[1]:
                if tag == p.TAG_BATTERY:
                    levels.add(v.hex())
    assert levels == {"30"}   # 48, one value only: not enough to confirm


def test_coverage_report():
    """Not an assertion on the protocol: shows which captured phone frames the encoder reproduces and which it leaves alone."""
    cats = {"known SET (reproduced)": 0, "GET (reproduced)": 0, "SET with other tags (parse/round trip only)": 0,
            "multi-packet (EQ blobs, parse/round trip only)": 0, "analytics GET 0x0201 (parse only)": 0, "other": 0}
    unknown_tags = {}
    for _, d, raw in APP:
        fr = p.parse_frame(raw)
        if fr.count != 1:
            cats["multi-packet (EQ blobs, parse/round trip only)"] += 1
        elif fr.command == p.CMD_GET:
            cats["GET (reproduced)"] += 1
        elif fr.command == p.CMD_ANALYTICS_GET:
            cats["analytics GET 0x0201 (parse only)"] += 1
        elif fr.command == p.CMD_SET:
            tlvs = p.parse_tlvs(fr.payload)
            if tlvs and all(t in p.FEATURES for t, _ in tlvs):
                cats["known SET (reproduced)"] += 1
            else:
                cats["SET with other tags (parse/round trip only)"] += 1
                for t, _ in tlvs:
                    if t not in p.FEATURES:
                        unknown_tags[t] = unknown_tags.get(t, 0) + 1
        else:
            cats["other"] += 1
    print("\nPhone frames by category:")
    for k, v in cats.items():
        print(f"  {v:4d}  {k}")
    print("Tags in SET frames the encoder does not build:", {hex(k): v for k, v in sorted(unknown_tags.items())})
    assert sum(cats.values()) == len(APP)
