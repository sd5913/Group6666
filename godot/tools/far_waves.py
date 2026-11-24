"""The far rhythm waves' data (scripts/view/far_waves.gd): every level's loudness envelope (levelN.json "loud", at
"loud_dt") averaged down to 1/8 s, with each song's length, and the final level's sections (the jam Theme's parts the
training levels stand for). Run after the level data changes:
    python tools/far_waves.py
writes data/levels/far_waves.json (small: the game reads only this, not the five big level files)."""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
LEVELS = os.path.join(os.path.dirname(HERE), "data", "levels")
DT = 0.125


def main():
    out = {"dt": DT, "levels": {}}
    for n in range(1, 6):
        with open(os.path.join(LEVELS, "level%d.json" % n), encoding="utf-8") as f:
            d = json.load(f)
        loud, src_dt = d["loud"], d["loud_dt"]
        per = max(1, round(DT / src_dt))
        env = [round(sum(loud[i:i + per]) / len(loud[i:i + per]), 3) for i in range(0, len(loud), per)]
        out["levels"][str(n)] = {"dur": d["dur"], "loud": env}
        if n == 5:
            out["sections"] = [{"id": s["id"], "t": s["t"], "end_t": s["end_t"]} for s in d.get("sections", [])]
    with open(os.path.join(LEVELS, "far_waves.json"), "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
    print("far_waves.json: %s" % ", ".join("L%s %d values" % (k, len(v["loud"])) for k, v in out["levels"].items()))


if __name__ == "__main__":
    main()
