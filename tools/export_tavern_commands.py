"""Extract the vector operations from the Pillow scene for the web runtime.

The browser executes these drawing operations and computes glows, gradients,
slimes, and pixel grading itself. No pre-rendered scene image is embedded.
"""

from __future__ import annotations

import json
from pathlib import Path

SOURCE = Path(__file__).with_name("render_slime_tavern.py")
DEST = Path(__file__).resolve().parent.parent / "tavern_commands.js"
DEST_GODOT = Path(__file__).resolve().parent.parent / "godot" / "data" / "tavern_commands.json"
source = SOURCE.read_text(encoding="utf-8")
world_start = source.index("# ---- Geometric scene")
post_start = source.index("def pixel_post")
namespace = {"__file__": str(SOURCE)}
exec(compile(source[:world_start], str(SOURCE), "exec"), namespace)

commands: list[dict] = []
for operation in ("poly", "rect", "ellipse", "line", "glow", "shaded_poly", "slime"):
    original = namespace[operation]

    def record(*args, _operation=operation, _original=original, **kwargs):
        commands.append({"op": _operation, "args": args, "kwargs": kwargs})
        return _original(*args, **kwargs)

    namespace[operation] = record

exec(compile(source[world_start:post_start], str(SOURCE), "exec"), namespace)
data = json.dumps(commands, ensure_ascii=False, separators=(",", ":"))
DEST.write_text(
    "// Generated from tools/render_slime_tavern.py; scene geometry, not bitmap data.\n"
    + "window.tavernGeometry = "
    + data
    + ";\n",
    encoding="utf-8",
)
DEST_GODOT.parent.mkdir(parents=True, exist_ok=True)
DEST_GODOT.write_text(data, encoding="utf-8")
print(f"{len(commands)} operations -> {DEST}, {DEST_GODOT}")
