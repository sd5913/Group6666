// The player's jelly squash, shared by its body and its outline (scripts/view/player_look.gd sets these).
// It pivots on the feet: squashing keeps the feet where they are and spreads the top more than the bottom,
// and a lean tips the top along the run more than the middle.

uniform float squash = 0.0;    // vertical stretch (+) / squash (-), volume kept by widening / narrowing
uniform float lean = 0.0;      // how far the top tips along the run (metres)
uniform float crouch = 1.0;    // standing height scale (slide)
uniform float feet = -0.7;     // local height of the feet (the pivot)
uniform float tall = 1.4;      // standing height

void jelly(inout vec3 v) {
	float w = clamp((v.y - feet) / tall, 0.0, 1.0);
	float sy = crouch * (1.0 + squash);
	float sx = inversesqrt(max(0.2, 1.0 + squash));
	v.y = feet + (v.y - feet) * sy;
	v.xz *= mix(1.0, sx, 0.35 + 0.65 * w);
	v.x += lean * w * w;
}
