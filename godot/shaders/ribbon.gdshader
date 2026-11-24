shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_opaque;
// A glide's ribbon (scripts/mechanics/glide.gd): a bright, see-through band in the accent under the player's feet,
// with stripes flowing backwards along it to show the speed and a glowing lower edge (COLOR.r 1 there). Its last beat
// turns pale to say "let go now"; once the band is over it fades away. UV.x is metres along the ribbon from its start.
// The arpeggio's notes under it are drawn into its top and front faces (shaders/note_marks.gdshaderinc): lighter
// stretches flashing on their notes, nothing standing out of the band where it ramps from note to note.

#include "res://shaders/note_marks.gdshaderinc"

uniform vec4 color : source_color = vec4(0.3, 0.8, 0.9, 0.85);
uniform float glow = 0.5;        // 0..1: brighter as the note calls for the jump and while it is held
uniform float warn = 0.0;        // 0..1: the last beat (from warn_u on) lit up
uniform float warn_u = 1e9;      // metres along where the last beat starts
uniform float fade = 1.0;        // the whole ribbon's opacity
uniform float flow = 4.0;        // how fast the stripes flow backwards (m/s)
uniform float stripe = 0.9;      // stripe spacing (metres)
uniform float body = 1.0;        // how bright the body is (its stripes and glowing edge stay as they are)

varying float u;

void vertex() {
	u = UV.x;
}

void fragment() {
	float s = step(0.55, fract((u + TIME * flow) / stripe));
	vec3 c = color.rgb * (0.95 + 0.6 * glow) * (1.0 - 0.3 * s) * mix(body, 1.0, s) + vec3(0.3) * s;  // (stripes lighter, gaps deeper)
	float w = warn * step(warn_u, u);
	c = mix(c, vec3(1.0), 0.5 * w);
	float mk = note_mark(u, UV, COLOR);
	vec3 tile = mix(color.rgb, vec3(1.0), 0.4);
	c = mix(c, tile, 0.6 * min(mk, 1.0)) + tile * 0.25 * max(mk - 0.35, 0.0);  // (on its note it blooms)
	c += (color.rgb * 0.6 + vec3(0.5)) * smoothstep(0.55, 1.0, COLOR.r);  // the lower edge glows (past 1: it blooms)
	ALBEDO = c;
	ALPHA = color.a * fade * smoothstep(0.0, 0.8, u);  // (its start comes in softly, where the player catches it)
}
