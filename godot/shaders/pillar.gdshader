shader_type spatial;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
#define INST uniform
#else
#define INST instance uniform
#endif
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

varying float world_y;

void vertex() {
	world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {

	float len = fade_len > 0.0 ? fade_len : fade_depth;
	float f = clamp(1.0 - max(abs(edge_y - world_y) - solid_len, 0.0) / max(len - solid_len, 0.01), 0.0, 1.0);
	f *= f;
	// The original glow, edge and fade uniforms continue to describe the moving track.
	float pulse = clamp(glow * boost, 0.0, 1.0);
	float cool = smoothstep(-0.08, 0.22, tint.b - tint.r);
	vec3 shadow = mix(vec3(0.23, 0.095, 0.21), vec3(0.16, 0.13, 0.29), cool);
	vec3 jelly = mix(vec3(0.78, 0.30, 0.48), vec3(0.51, 0.40, 0.71), cool);
	vec3 gloss = mix(vec3(0.99, 0.63, 0.71), vec3(0.73, 0.67, 0.91), cool);
	float face = 0.72 + 0.28 * max(dot(NORMAL, normalize(vec3(-0.35, 0.75, 0.48))), 0.0);
	float bands = floor(f * 6.0 + 0.25) / 6.0;
	vec3 surface = mix(shadow, jelly, bands) * face;
	float cap = 1.0 - smoothstep(0.13, 0.29, abs(edge_y - world_y));
	float scallop = step(0.38, fract(UV.x * 3.0 + 0.26)) * step(0.95, f);
	surface = mix(surface, gloss, cap * (0.66 + pulse * 0.24));
	surface = mix(surface, gloss, scallop * 0.19);
	vec2 fleck = fract(UV * vec2(6.0, 4.0) + vec2(0.13, 0.31));
	float bubble = step(0.72, fleck.x) * (1.0 - step(0.82, fleck.x))
		* step(0.22, fleck.y) * (1.0 - step(0.30, fleck.y));
	ALBEDO = mix(surface, gloss, bubble * f * 0.26);
	EMISSION = jelly * (0.025 + 0.14 * pulse) * f;
	ROUGHNESS = 0.65;
}
