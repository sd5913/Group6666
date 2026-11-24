shader_type spatial;
render_mode unshaded, cull_disabled;
// One MIDI note of the background (scripts/view/midi_background.gd), drawn through a MultiMesh. Resting, it is a pale
// shape fading into the sky with its layer's depth; as it sounds it swells and turns to its full, deep colour (the
// sky is pale, so a hit shows by colour, not by brightness), lingering a moment on drums; just before, it firms up a
// little. Per instance: COLOR = the note's colour, INSTANCE_CUSTOM = (start s, end s, seed 0..1, velocity 0..1).

uniform float now = 0.0;
uniform vec4 sky : source_color = vec4(0.98, 0.87, 0.74, 1.0);
uniform float fade = 0.5;      // how far this layer has faded into the sky at rest
uniform float spin = 0.0;      // turning speed (radians per second)
uniform float wobble = 0.0;    // gentle rocking (radians)
uniform float flash = 1.0;     // how strongly a hit shows
uniform float swell = 0.45;    // extra size on the hit
uniform float decay = 6.0;     // how fast a hit fades (per second; drums are slower)
uniform float energy = 0.0;    // the song's intensity now (6d climax up to 1; 6b softer sections below 0)
uniform float pulse = 0.0;     // a phrase has just started (5a)
uniform float hit_sat = 0.6;   // how saturated a note gets as it sounds

varying vec3 col;
varying float lit;

void vertex() {
	vec4 c = INSTANCE_CUSTOM;
	float age = now - c.x;
	float hit = age >= 0.0 ? exp(-age * decay) : 0.0;
	float held = (now >= c.x && now <= c.y) ? 1.0 : 0.0;
	float soon = age < 0.0 ? smoothstep(-0.6, 0.0, age) : 0.0;
	lit = clamp(flash * max(hit, 0.35 * held) + 0.2 * soon + 0.5 * pulse, 0.0, 1.0);
	float a = c.z * 6.2832 + now * spin * (1.0 + max(energy, 0.0));
	float b = wobble * sin(now * 0.9 + c.z * 6.2832);
	mat3 ry = mat3(vec3(cos(a), 0.0, -sin(a)), vec3(0.0, 1.0, 0.0), vec3(sin(a), 0.0, cos(a)));
	mat3 rx = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, cos(b), sin(b)), vec3(0.0, -sin(b), cos(b)));
	mat3 r = rx * ry;
	float grow = 1.0 + swell * (1.0 + max(energy, 0.0)) * hit * (0.6 + 0.4 * c.w) + 0.25 * pulse;
	VERTEX = r * VERTEX * grow;
	NORMAL = r * NORMAL;
	col = COLOR.rgb;
}

void fragment() {
	// a fixed light from the upper left (view space), so the facets read without real lights
	float shade = 0.72 + 0.28 * clamp(dot(NORMAL, normalize(vec3(-0.4, 0.8, 0.45))), 0.0, 1.0);
	vec3 rest = mix(col * shade, sky.rgb, clamp(fade * (1.0 - 0.6 * energy), 0.0, 1.0));
	// the hit: the note's own hue at hit_sat saturation, a little deeper than the pale sky (never as strong as the
	// accent colour the mechanics wear)
	float hi = max(col.r, max(col.g, col.b));
	float lo = min(col.r, min(col.g, col.b));
	vec3 hue = (col - vec3(lo)) / max(hi - lo, 0.001);
	vec3 vivid = mix(vec3(1.0), hue, hit_sat) * 0.86 * shade;
	ALBEDO = mix(rest, vivid, lit);
}
