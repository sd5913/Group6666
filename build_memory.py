"""Build the themed browser pack from the untouched Midi Runner export."""

from hashlib import md5
import json
from pathlib import Path
import struct


ROOT = Path(__file__).resolve().parent
SOURCES = ROOT / "memory-src"
ENTRY = struct.Struct("<QQ16sI")


def splice(text, old, new):
    if text.count(old) != 1:
        raise ValueError(f"Expected one shader anchor: {old}")
    return text.replace(old, new, 1)


def replace_fragment(text, body):
    return text[:text.index("void fragment() {")] + "void fragment() {\n" + body + "\n}\n"


def slime_palette_shader():
    palette = json.loads((ROOT / "slime-palette.json").read_text(encoding="utf-8"))
    declarations = []
    for name, color in palette.items():
        components = [int(color[i:i + 2], 16) / 255 for i in (1, 3, 5)]
        rgb = ", ".join(f"{component:.5f}" for component in components)
        declarations.append(f"const vec3 SLIME_{name.upper()} = vec3({rgb});")
    return "\n".join(declarations) + "\n"


def add_autoload(project, key, path):
    if project[:4] != b"ECFG":
        raise ValueError("Expected a binary Godot project configuration")
    count, = struct.unpack_from("<I", project, 4)
    name = key.encode()
    if name in project:
        raise ValueError("Autoload already exists")
    value = path.encode()
    # Godot Variant::STRING, UTF-8 bytes and zero padding to a four-byte boundary.
    variant = struct.pack("<II", 4, len(value)) + value + b"\0" * (-len(value) % 4)
    setting = struct.pack("<I", len(name)) + name + struct.pack("<I", len(variant)) + variant
    return project[:4] + struct.pack("<I", count + 1) + project[8:] + setting


def read_pack(pack):
    if pack[:8] != b"GDPC\x04\0\0\0":
        raise ValueError("Expected this export's Godot version 4 pack format")
    base, directory = struct.unpack_from("<QQ", pack, 24)
    count, = struct.unpack_from("<I", pack, directory)
    cursor = directory + 4
    entries = {}
    for _ in range(count):
        size, = struct.unpack_from("<I", pack, cursor)
        cursor += 4
        name = pack[cursor:cursor + size].rstrip(b"\0").decode()
        cursor += size
        entries[name] = ENTRY.unpack_from(pack, cursor)
        cursor += ENTRY.size
    if cursor != len(pack):
        raise ValueError("Unexpected data following the original pack directory")
    return base, directory, entries


def build():
    original = (ROOT / "index.pck").read_bytes()
    base, directory, entries = read_pack(original)

    def read(name):
        offset, size, _, flags = entries[name]
        if flags:
            raise ValueError(f"Unsupported flags for {name}")
        return original[base + offset:base + offset + size]

    post = read("shaders/pixel_post.gdshader").decode()
    cavern = (SOURCES / "cavern.gdshaderinc").read_text(encoding="utf-8")
    post = splice(post, "void fragment() {", cavern + "\nvoid fragment() {")
    post = splice(post, "COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);", """vec2 cave_cell = vec2(cell.x, floor(SCREEN_UV.y * 216.0));
	COLOR = vec4(clamp(cavern_grade(c, cave_cell), 0.0, 1.0), 1.0);""")

    pillar = read("shaders/pillar.gdshader").decode(errors="replace")
    original_body = pillar.split("void fragment() {", 1)[1].split("\tvec3 deep", 1)[0]
    pillar = replace_fragment(
        pillar, original_body.rstrip() + "\n" + (SOURCES / "pillar-surface.gdshaderinc").read_text().rstrip()
    )

    wave = read("shaders/far_wave.gdshader").decode(errors="replace")
    wave = splice(wave, "ALBEDO = mix(mix(sky.rgb, back_low.rgb, smoothstep(0.0, 1.0, x)), far_turn(top_col.rgb, low_col.rgb, x), vis);", """float layer = clamp(dot(top_col.rgb, vec3(0.299, 0.587, 0.114)), 0.0, 1.0);
	vec3 deep = vec3(0.14, 0.09, 0.20);
	vec3 light = mix(vec3(0.24, 0.12, 0.34), vec3(0.34, 0.20, 0.44), layer);
	float band = floor((1.0 - x) * 6.0 + 0.25) / 6.0;
	ALBEDO = mix(deep, mix(deep, light, band), vis);""")

    plate = read("shaders/far_plate.gdshader").decode(errors="replace")
    plate = splice(plate, "ALBEDO = far_turn(top_col.rgb, low_col.rgb, clamp((d - lit) / max(dark_len, 0.01), 0.0, 1.0));",
                   "ALBEDO = vec3(0.15, 0.10, 0.22);")

    palette = slime_palette_shader()
    shape = '#include "res://shaders/slime-shape.gdshaderinc"\n'
    jelly = '#include "res://shaders/jelly.gdshaderinc"\n'
    skin = (SOURCES / "slime-skin.gdshaderinc").read_text(encoding="utf-8")
    body = (
        "shader_type spatial;\nrender_mode unshaded, shadows_disabled;\n"
        + jelly + shape + palette
        + "uniform vec4 body : source_color = vec4(1.0);\nuniform float rim = 0.65;\n"
        + skin
    )
    outline = read("shaders/jelly_outline.gdshader").decode().replace("\r", "")
    outline = splice(outline, jelly, jelly + shape + palette)
    outline = splice(outline, "jelly(VERTEX);", "slime_shape(VERTEX);")
    outline = splice(outline, "ALBEDO = line.rgb;", "ALBEDO = pow(SLIME_OUTLINE, vec3(1.52));")

    replacements = {
        "project.binary": add_autoload(read("project.binary"), "autoload/TavernBridge", "*res://tavern_bridge.gd"),
        "tavern_bridge.gd": (SOURCES / "tavern_bridge.gd").read_bytes(),
        "shaders/pixel_post.gdshader": post.encode(),
        "shaders/pillar.gdshader": pillar.encode(),
        "shaders/far_wave.gdshader": wave.encode(),
        "shaders/far_plate.gdshader": plate.encode(),
        "shaders/jelly.gdshader": body.encode(),
        "shaders/jelly_outline.gdshader": outline.encode(),
        "shaders/slime-shape.gdshaderinc": (SOURCES / "slime-shape.gdshaderinc").read_bytes(),
    }

    # Unmodified resources keep their original offsets and bytes, including music and game scripts.
    output = bytearray(original[:directory])
    for name, data in replacements.items():
        output += b"\0" * (-len(output) % 16)
        entries[name] = (len(output) - base, len(data), md5(data).digest(), 0)
        output += data
    output += b"\0" * (-len(output) % 16)
    struct.pack_into("<Q", output, 32, len(output))
    output += struct.pack("<I", len(entries))
    for name, entry in entries.items():
        raw = name.encode()
        raw += b"\0" * (-len(raw) % 4)
        output += struct.pack("<I", len(raw)) + raw + ENTRY.pack(*entry)
    (ROOT / "tavern-game.pck").write_bytes(output)


if __name__ == "__main__":
    build()
