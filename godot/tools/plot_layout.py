"""Side view of a dumped level layout (dump_layout.gd): pillars, drums, jaws at their clap, springs, stars,
air-dash rings, gaps and the autoplay path, split into rows so details stay readable."""
import json, math, sys
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle, Polygon, Circle

src, out = sys.argv[1], sys.argv[2]
ROWS = int(sys.argv[3]) if len(sys.argv) > 3 else 4
d = json.load(open(src, encoding="utf-8"))
theme = "#" + d["theme"]
x0 = min(p[0] for p in d["path"]) - 2
x1 = d["goal"] + 6
span = (x1 - x0) / ROWS
fig, axes = plt.subplots(ROWS, 1, figsize=(26, 4.2 * ROWS))
tilt = math.radians(35)
KIND = {"1a": "#db3d3d", "1b": "#4d73f2", "1c": "#f2b826"}
for r, ax in enumerate(axes):
    a, b = x0 + r * span, x0 + (r + 1) * span
    ax.set_xlim(a, b)
    ax.set_ylim(-3.5, 7.5)
    ax.set_aspect("equal")
    ax.set_facecolor("#f4f1ea")
    for bx in d["boosts"]:
        ax.axvspan(bx[0], bx[1], color="#ffe08a", alpha=0.45, lw=0)
    for sx in d["shapes"]:
        ax.axvline(sx, color="#999", lw=0.8, ls=":")
    for p in d["pits"]:
        ax.axvspan(p[0], p[1], ymin=0, ymax=0.06, color="#333", alpha=0.5, lw=0)
    for xa, xb, base, is_drum in d["mech"]:
        ax.add_patch(Rectangle((xa + 0.06, base - 3), max(0.05, xb - xa - 0.12), 3, color=theme, alpha=0.9 if not is_drum else 0.6, lw=0))
    for x, rr, base, amp in d["bars"]:
        ax.add_patch(Rectangle((x - rr, base - 3), 2 * rr, 3 + 0.5 * amp * 2.4, color=theme, alpha=0.45, lw=0))
    for dr in d["drums"]:
        # skin line through its centre, tilted 35 deg towards the goal
        cx, cy, rr = dr["x"], dr["top"] + dr["skin_c"], dr["r"]
        dx, dy = rr * math.cos(tilt), rr * math.sin(tilt)
        ax.add_patch(Polygon([(cx - dx, cy + dy), (cx + dx, cy - dy), (cx + dx, dr["top"]), (cx - dx - 0.2, dr["top"])], color=KIND.get(dr["kind"], "#db3d3d"), alpha=0.85, lw=0))
        ax.plot([cx - dx, cx + dx], [cy + dy, cy - dy], color="white", lw=2)
        ax.text(cx, dr["top"] - 0.6, dr["mode"], ha="center", fontsize=8)
    for j in d["jaws"]:
        col = "#c93a8a" if not j["big"] else "#e7a2cf"
        ax.add_patch(Rectangle((j["x"] - j["w"] / 2, j["c"] + j["gap"]), j["w"], 8, color=col, alpha=0.75, lw=0))
        ax.add_patch(Rectangle((j["x"] - j["w"] / 2, j["c"] - j["gap"] - 8), j["w"], 8, color=col, alpha=0.75, lw=0))
    for sx, sy, press in d["springs"]:
        ax.add_patch(Rectangle((sx - 0.4, sy), 0.8, 0.3, color="#2fbf5f" if press else "#9be3b0", lw=0))
    for sx, sy in d["stars"]:
        ax.plot(sx, sy, marker="*", color="#e6b800", ms=12)
    for rx, ry in d["rings"]:
        ax.add_patch(Circle((rx, ry), 0.56, fill=False, ec="#c93a8a", lw=2))
    px = [p[0] for p in d["path"] if a - 1 <= p[0] <= b + 1]
    py = [p[1] for p in d["path"] if a - 1 <= p[0] <= b + 1]
    ax.plot(px, [y - 0.7 for y in py], color="#111", lw=1.2)  # feet
    ax.plot(px, [y + 0.7 for y in py], color="#111", lw=0.5, alpha=0.5)  # head
    ax.axvline(d["goal"], color="#e04a8a", lw=3)
    ax.tick_params(labelsize=7)
fig.suptitle("level %s  (%s)  — path: feet (thick) / head (thin); yellow = 3a boost bars; dotted = terrain shape change" % (d["level"], d["state"]), fontsize=14)
fig.tight_layout()
fig.savefig(out, dpi=70)
print("saved", out)
