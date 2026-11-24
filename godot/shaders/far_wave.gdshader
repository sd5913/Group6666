shader_type spatial;
// The far rhythm waves (scripts/view/far_waves.gd): one row of thin columns per song, a loudness skyline far behind
// the run. Unlit, lit at the top and dark below like the pillars of the run, all in its row's haze (colours worked out
// each frame in far_waves.gd): `top_col` (its level's colour, as bright as the sky, so against the sky only its hue
// draws it) for `lit` metres down from its top, then within `dark_len` metres turning into `low_col` (as dark as the
// floor hazed as far as the row — deeper rows' dark paler — still in its hue; its saturation there by halfway:
// far_turn.gdshaderinc). Each column moves with the music: its height over the row's lowest top (`foot`) is scaled by
// its visualizer band's live level (INSTANCE_CUSTOM.x = the band) and stretches on the level's kicks; its bottom stays
// down on the floor.
render_mode unshaded, shadows_disabled;

#include "res://shaders/far_turn.gdshaderinc"

uniform vec4 sky : source_color = vec4(0.98, 0.87, 0.74, 1.0);       // set every frame
uniform vec4 top_col : source_color = vec4(0.98, 0.87, 0.74, 1.0);   // set every frame
uniform vec4 low_col : source_color = vec4(0.12, 0.12, 0.16, 1.0);   // set every frame
uniform vec4 back_low : source_color = vec4(0.12, 0.12, 0.16, 1.0);  // the plate behind it down there (set every frame)
uniform float lit = 4.0;        // how far down from its top a column keeps its top colour (metres)
uniform float dark_len = 8.0;   // then over how far it turns dark (metres)
uniform float bands[12];        // the visualizer bands' live levels (0..1), set every frame
uniform float still = 0.45;     // a column's height over `foot` with its band silent (the rest comes with the band)
uniform float foot = 0.0;       // the row's lowest top (world y): the columns grow and shrink over it
uniform float beat = 0.0;       // the tops stretch up by this much of their height over `foot` (on a kick)
uniform float vis = 1.0;        // 0: melted into the backdrop (the final level's rows outside their section)

varying float world_y;
varying float top_y;

void vertex() {
	// a unit box from the floor up to the column's loudest top: only the top moves
	float bottom = (MODEL_MATRIX * vec4(0.0, -0.5, 0.0, 1.0)).y;
	float full = (MODEL_MATRIX * vec4(0.0, 0.5, 0.0, 1.0)).y;
	float level = bands[clamp(int(INSTANCE_CUSTOM.x + 0.5), 0, 11)];
	top_y = foot + (full - foot) * (still + (1.0 - still) * level) * (1.0 + beat);
	VERTEX.y = -0.5 + (VERTEX.y + 0.5) * (top_y - bottom) / max(full - bottom, 0.01);
	world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	float x = clamp((top_y - world_y - lit) / max(dark_len, 0.01), 0.0, 1.0);
	float layer = clamp(dot(top_col.rgb, vec3(0.299, 0.587, 0.114)), 0.0, 1.0);
	vec3 deep = vec3(0.14, 0.09, 0.20);
	vec3 light = mix(vec3(0.24, 0.12, 0.34), vec3(0.34, 0.20, 0.44), layer);
	float band = floor((1.0 - x) * 6.0 + 0.25) / 6.0;
	ALBEDO = mix(deep, mix(deep, light, band), vis);
}
