shader_type spatial;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
#define INST uniform
#else
#define INST instance uniform
#endif
#include "res://shaders/cave_stone.gdshaderinc"
// Pillars: the level's theme colour as a vertical gradient, bright at the working end (the top of a standing column,
// the bottom of a hanging one) and fading away from it — down into the dark abyss for the run, or, with far_sky, into
// the sky for columns hanging from above (so they don't weigh on the picture) — glowing with the music.
// Everything per pillar is an instance uniform, so all pillars share this one material.

INST vec4 tint : source_color = vec4(1.0, 0.5, 0.12, 1.0);
INST float glow = 0.0;     // 0..1, driven by the music every frame
INST float edge_y = 0.0;   // world height of the column's working end
INST float boost = 1.0;    // caps glow harder than stems
INST float fade_len = 0.0; // metres from the working end to the far colour (0: fade_depth)
INST float far_sky = 0.0;  // 1: the far end turns into the sky instead of the dark
INST float solid_len = 0.0; // metres from the working end that keep the full colour before the fade starts

uniform float fade_depth = 5.0;        // metres from the working end down to full darkness
uniform float glow_energy = 2.2;
uniform vec4 sky : source_color = vec4(0.98, 0.87, 0.74, 1.0);  // set every frame (5-5 warm / cool)
uniform int cave_level = 1;

varying float world_y;
varying vec2 rock_xz;

void vertex() {
	world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
	rock_xz = vec2(VERTEX.x * length(MODEL_MATRIX[0].xyz), VERTEX.z * length(MODEL_MATRIX[2].xyz));
}

void fragment() {
	float depth = abs(edge_y - world_y);
	float len = fade_len > 0.0 ? fade_len : fade_depth;
	float f = clamp(1.0 - max(depth - solid_len, 0.0) / max(len - solid_len, 0.01), 0.0, 1.0);
	float pulse = clamp(glow * boost, 0.0, 1.0);
	vec3 shadow;
	vec3 stone;
	vec3 vein;
	cave_palette(cave_level, shadow, stone, vein);
	stone *= mix(0.77, 1.12, max(tint.r, max(tint.g, tint.b)));
	vec3 rock = cave_strata(vec2(rock_xz.x + rock_xz.y, depth), cave_level, f, shadow, stone, vein);
	float rim = 1.0 - smoothstep(0.11, 0.22, depth);
	vec3 frost = mix(vec3(0.89, 0.94, 0.99), vein, 0.18);
	ALBEDO = mix(rock, frost, rim * 0.94);
	EMISSION = vein * (0.025 + 0.045 * pulse) * f + frost * rim * (0.16 + 0.15 * pulse);
	ROUGHNESS = 0.87;
	SPECULAR = 0.20;
}
