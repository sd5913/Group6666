shader_type spatial;
// The plate behind the far rhythm waves (scripts/view/far_waves.gd), the end of their haze: what the gaps between the
// columns show. At every height it is what a column of the deepest row with its top at that row's middle height would
// be there (the same lit top, turn and dark below, colours set every frame), so a gap is always the colour of the
// columns beside it; over the lit part it fades in from nothing, so it has no edge against the sky.
render_mode unshaded, shadows_disabled, blend_mix, cull_disabled;

#include "res://shaders/far_turn.gdshaderinc"

uniform vec4 top_col : source_color = vec4(0.98, 0.87, 0.74, 1.0);  // set every frame
uniform vec4 low_col : source_color = vec4(0.12, 0.12, 0.16, 1.0);  // set every frame
uniform float top = 0.0;        // that column's top (world y)
uniform float lit = 4.0;        // its lit part (metres)
uniform float dark_len = 8.0;   // and how far it then turns dark (metres)

varying float world_y;

void vertex() {
	world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	float d = top - world_y;
	ALBEDO = vec3(0.15, 0.10, 0.22);
	ALPHA = smoothstep(0.0, max(lit, 0.01), d);
}
