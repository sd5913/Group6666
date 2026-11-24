// The notes lying along a glide's ribbon or a tread (scripts/mechanics/glide.gd, steps.gd), drawn into its own
// surface so nothing stands out of it: each note's stretch lighter, flashing on its note. UV.x is metres along it;
// COLOR.g marks a top face (the marks across its middle), COLOR.b a front face (the marks on its upper part).

uniform float note_u0[48];   // where each note's stretch starts and ends (metres along)
uniform float note_u1[48];
uniform float note_t[48];    // and its song time
uniform int notes = 0;
uniform float now = 0.0;     // song time (set every frame)

// 0 off the notes; on one, 0.35 plus its flash (2.5 on its note, gone again within a fraction of a second).
float note_mark(float u, vec2 uv, vec4 col) {
	float band = col.g > 0.5 ? step(abs(uv.y - 0.5), 0.35) : (col.b > 0.5 ? step(uv.y, 0.45) : 0.0);
	if (band <= 0.0) {
		return 0.0;
	}
	float m = 0.0;
	for (int i = 0; i < notes; i++) {
		if (u >= note_u0[i] && u < note_u1[i]) {
			float lit = now >= note_t[i] ? 2.5 * exp(-(now - note_t[i]) * 6.0) : 0.0;
			m = max(m, 0.35 + lit);
		}
	}
	return m * band;
}
