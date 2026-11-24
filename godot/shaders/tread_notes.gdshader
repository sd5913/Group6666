shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
// A tread's notes (scripts/mechanics/steps.gd): a skin lying flush on its top and front faces that shows nothing but
// the notes' marks (shaders/note_marks.gdshaderinc), so no layer stands out of the tread.

#include "res://shaders/note_marks.gdshaderinc"

uniform vec4 color : source_color = vec4(1.0);  // the tread's colour (the marks are a lighter one)
uniform float fade = 1.0;

void fragment() {
	float mk = note_mark(UV.x, UV, COLOR);
	vec3 mark = mix(color.rgb, vec3(1.0), 0.45);
	ALBEDO = mark * (0.9 + 0.25 * max(mk - 0.35, 0.0));
	ALPHA = clamp(mk, 0.0, 1.0) * 0.85 * fade;
}
