"""JBL Tune 780NC control protocol ("protocol4"): frame encoder and parser.

Builds and parses bytes only. It never talks to a device. Spec: notes/protocol.md.
All numbers little-endian. Frame = identifier u16, command u16, count u8, index u8, size u16, payload.
"""
import struct
from dataclasses import dataclass

IDENT = 0xDD00          # bytes 00 dd
IDENT_SYNC = 0xDD01     # bytes 01 dd (clock sync frames; meaning of first byte unknown)

CMD_GET = 0x0001
CMD_SET = 0x0002
CMD_NOTIFY_APP = 0x0003
CMD_NOTIFY_DEVICE = 0x0004
CMD_ANALYTICS_GET = 0x0201

# Never build these (notes/protocol.md section 8).
OFF_LIMITS_COMMANDS = {0x00FF, 0x0101, 0x0102, 0x0103, 0x0104, 0x02FF}
OFF_LIMITS_TAGS = {
    0x000F,                          # FactoryReset
    0x1F00,                          # LaunchOTAMode
    0x0BA0, 0x0BA5,                  # LE Audio (reboots), BT pairing mode
    0x0B81, 0x0B86,                  # Auracast, unexplained
    0x003E, 0x004A, 0x004B, 0x0053, 0x0054,  # authentication
    0x100F,                          # Smart Audio & Video (drops connection)
    0x0E01, 0x0E02,                  # EQ, not decoded
}

TAG_BATTERY = 0x000D
TAG_ANC = 0x0018
TAG_AMBIENT = 0x0019
TAG_TALKTHRU = 0x001A
TAG_BALANCE = 0x0015
TAG_VOICE_AWARE = 0x0023
TAG_SPATIAL = 0x0022
TAG_AUTO_OFF = 0x0012
TAG_VOICE_PROMPT = 0x0C40
TAG_VOICE_PROMPT_LANG = 0x0C41
TAG_HEARTBEAT = 0x0002
TAG_BTN_MFB_SINGLE = 0x0F82
TAG_BTN_MFB_HOLD = 0x0F83
TAG_BTN_MFB_DOUBLE = 0x0F84
TAG_BTN_ANC_SINGLE = 0x0F85
TAG_BTN_MFB_TRIPLE = 0x0F88

# tag -> (name, codec). Codecs: sl1 = StatusLevel1, sl2 = StatusLevel2, u8 = one byte, none = empty
FEATURES = {
    TAG_ANC: ("anc", "sl1"),
    TAG_AMBIENT: ("ambient_aware", "sl1"),
    TAG_TALKTHRU: ("talkthru", "sl1"),
    TAG_VOICE_AWARE: ("voice_aware", "sl1"),
    TAG_BALANCE: ("balance", "sl1"),
    TAG_SPATIAL: ("spatial", "sl1"),
    TAG_AUTO_OFF: ("auto_power_off", "sl2"),
    TAG_VOICE_PROMPT: ("voice_prompt", "sl1"),
    TAG_VOICE_PROMPT_LANG: ("voice_prompt_lang", "u8"),
    TAG_BTN_MFB_SINGLE: ("btn_mfb_single", "u8"),
    TAG_BTN_MFB_HOLD: ("btn_mfb_hold", "u8"),
    TAG_BTN_MFB_DOUBLE: ("btn_mfb_double", "u8"),
    TAG_BTN_ANC_SINGLE: ("btn_anc_single", "u8"),
    TAG_BTN_MFB_TRIPLE: ("btn_mfb_triple", "u8"),
    TAG_HEARTBEAT: ("heartbeat", "none"),
}
NAME_TO_TAG = {name: tag for tag, (name, _) in FEATURES.items()}

# Tags the encoder will build in a SET. Subset of FEATURES; only verified ones.
WRITABLE_TAGS = set(FEATURES)

# Gesture function IDs (code + capture)
G_PLAY_PAUSE, G_EQ_ONOFF, G_SPATIAL, G_VOICE_ASSISTANT = 0x08, 0xC8, 0xC2, 0xA1
G_ANC_AA_OFF, G_ANC_AA, G_ANC_OFF, G_AA_OFF = 0x09, 0x0B, 0x0C, 0x0D

SPATIAL_MODES = {"music": 2, "movie": 1, "game": 3}


@dataclass(frozen=True)
class Frame:
    identifier: int
    command: int
    count: int
    index: int
    payload: bytes

    def encode(self):
        return struct.pack("<HHBBH", self.identifier, self.command, self.count, self.index, len(self.payload)) + self.payload


def parse_frame(data):
    if len(data) < 8:
        raise ValueError("frame shorter than header")
    ident, cmd, count, index, size = struct.unpack("<HHBBH", data[:8])
    if size != len(data) - 8:
        raise ValueError(f"payload size {size} does not match {len(data) - 8} bytes")
    return Frame(ident, cmd, count, index, bytes(data[8:]))


def parse_tlvs(payload):
    out, i = [], 0
    while i < len(payload):
        if i + 4 > len(payload):
            raise ValueError("truncated TLV header")
        tag, ln = struct.unpack("<HH", payload[i:i + 4])
        if i + 4 + ln > len(payload):
            raise ValueError("truncated TLV value")
        out.append((tag, bytes(payload[i + 4:i + 4 + ln])))
        i += 4 + ln
    return out


def encode_tlvs(tlvs):
    return b"".join(struct.pack("<HH", tag, len(v)) + v for tag, v in tlvs)


def parse_status_tlvs(payload):
    """Device replies and notifications: status u16 then TLVs. Returns (status, tlvs)."""
    if len(payload) < 2:
        raise ValueError("missing status")
    return struct.unpack("<H", payload[:2])[0], parse_tlvs(payload[2:])


def encode_status_tlvs(status, tlvs):
    return struct.pack("<H", status) + encode_tlvs(tlvs)


# --- value codecs -------------------------------------------------------------

def encode_sl1(status, level):
    if not 0 <= level <= 0x7F:
        raise ValueError("level out of range")
    return bytes([((1 if status else 0) << 7) | level])


def decode_sl1(value):
    if len(value) != 1:
        raise ValueError("StatusLevel1 is one byte")
    return value[0] >> 7, value[0] & 0x7F


def encode_sl2(status, level):
    if not 0 <= level <= 0x7FFF:
        raise ValueError("level out of range")
    return struct.pack("<H", ((1 if status else 0) << 15) | level)


def decode_sl2(value):
    if len(value) != 2:
        raise ValueError("StatusLevel2 is two bytes")
    v = struct.unpack("<H", value)[0]
    return v >> 15, v & 0x7FFF


def decode_battery(value):
    """UNVERIFIED: tag 0x0d, one sample (0x30 = 48, app showed 48%). Returns (bit7, level)."""
    return decode_sl1(value)


# --- semantic layer -----------------------------------------------------------

def decode_feature(tag, value):
    """Known tag -> (name, args dict). Raises KeyError for unknown tags."""
    name, codec = FEATURES[tag]
    if codec == "sl1":
        s, l = decode_sl1(value)
        return name, {"status": s, "level": l}
    if codec == "sl2":
        s, l = decode_sl2(value)
        return name, {"status": s, "level": l}
    if codec == "u8":
        if len(value) != 1:
            raise ValueError("u8 value must be one byte")
        return name, {"value": value[0]}
    if value:
        raise ValueError("expected empty value")
    return name, {}


def encode_feature(name, **args):
    tag = NAME_TO_TAG[name]
    codec = FEATURES[tag][1]
    if codec == "sl1":
        return tag, encode_sl1(args["status"], args["level"])
    if codec == "sl2":
        return tag, encode_sl2(args["status"], args["level"])
    if codec == "u8":
        return tag, bytes([args["value"]])
    return tag, b""


# --- frame builders (bytes only, nothing is sent) -------------------------------

def build_get(tags, identifier=IDENT):
    return Frame(identifier, CMD_GET, 1, 0, b"".join(struct.pack("<H", t) for t in tags)).encode()


def build_set(tlvs, identifier=IDENT):
    for tag, _ in tlvs:
        if tag in OFF_LIMITS_TAGS:
            raise PermissionError(f"tag 0x{tag:04x} is off limits")
        if tag not in WRITABLE_TAGS:
            raise PermissionError(f"tag 0x{tag:04x} is not a verified writable tag")
    return Frame(identifier, CMD_SET, 1, 0, encode_tlvs(tlvs)).encode()


def build_frame(command, payload, identifier=IDENT, count=1, index=0):
    if command in OFF_LIMITS_COMMANDS:
        raise PermissionError(f"command 0x{command:04x} is off limits")
    if command == CMD_SET and count == 1:
        try:
            tags = [t for t, _ in parse_tlvs(payload)]
        except Exception as e:
            raise PermissionError(f"cannot verify the tags of this SET payload: {e}")
        for t in tags:
            if t in OFF_LIMITS_TAGS:
                raise PermissionError(f"tag 0x{t:04x} is off limits")
    return Frame(identifier, command, count, index, payload).encode()


def set_anc(on):
    return build_set([encode_feature("anc", status=on, level=0x7F)])


def set_all_noise_off():
    return build_set([encode_feature("anc", status=0, level=0x7F)])


def set_ambient_aware():
    return build_set([encode_feature("ambient_aware", status=1, level=0x7F)])


def set_talkthru():
    return build_set([encode_feature("talkthru", status=1, level=0x7F)])


def set_voice_aware(level, on=True):
    """level 1 Low, 2 Mid, 3 High. When off the app keeps the last level bits."""
    if level not in (1, 2, 3):
        raise ValueError("level must be 1, 2 or 3")
    return build_set([encode_feature("voice_aware", status=on, level=level)])


def set_balance(value, on=True):
    """value -16..+16; stored as 50 + value."""
    if not -16 <= value <= 16:
        raise ValueError("balance out of range")
    return build_set([encode_feature("balance", status=on, level=50 + value)])


def set_spatial(mode, on=True):
    return build_set([encode_feature("spatial", status=on, level=SPATIAL_MODES[mode])])


def set_auto_power_off(seconds, on=True):
    return build_set([encode_feature("auto_power_off", status=on, level=seconds)])


def set_voice_prompt(on, lang=1):
    return build_set([encode_feature("voice_prompt", status=on, level=0x7F),
                      encode_feature("voice_prompt_lang", value=lang)])


def set_gesture(name, function_id):
    if not name.startswith("btn_"):
        raise ValueError("not a button feature")
    return build_set([encode_feature(name, value=function_id)])


def build_heartbeat():
    return build_set([encode_feature("heartbeat")])
