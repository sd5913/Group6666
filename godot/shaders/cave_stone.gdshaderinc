// Shared foreground stone for platform slabs and the closing columns.
void cave_palette(int level, out vec3 shadow, out vec3 stone, out vec3 vein) {
	if (level == 2) {
		shadow = vec3(0.075, 0.19, 0.22);
		stone = vec3(0.18, 0.53, 0.47);
		vein = vec3(0.36, 0.77, 0.70);
	} else if (level == 3) {
		shadow = vec3(0.17, 0.11, 0.25);
		stone = vec3(0.43, 0.28, 0.62);
		vein = vec3(0.70, 0.50, 0.85);
	} else if (level == 4) {
		shadow = vec3(0.075, 0.13, 0.26);
		stone = vec3(0.24, 0.41, 0.65);
		vein = vec3(0.57, 0.71, 0.92);
	} else if (level == 5) {
		shadow = vec3(0.22, 0.09, 0.15);
		stone = vec3(0.52, 0.22, 0.33);
		vein = vec3(0.78, 0.45, 0.58);
	} else {
		shadow = vec3(0.18, 0.105, 0.23);
		stone = vec3(0.53, 0.25, 0.42);
		vein = vec3(0.78, 0.48, 0.65);
	}
}

float stone_hash(vec2 tile) {
	return fract(sin(dot(tile, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 cave_strata(vec2 face_pos, int level, float fade, vec3 shadow, vec3 stone, vec3 vein) {
	// Quantize in metres along the surface so the pattern moves with each slab.
	vec2 cell = floor(face_pos * 15.0) / 15.0;
	float slope = level == 3 ? 0.43 : (level == 4 ? -0.16 : 0.08);
	float offset = (stone_hash(vec2(floor(cell.x * 2.0), 3.0)) - 0.5) * 0.07;
	float layer = (cell.y + cell.x * slope + offset) * (level == 2 ? 2.6 : 2.0);
	float band = fract(layer);
	float tile = stone_hash(floor(cell * vec2(7.0, 8.0)));
	float tone = clamp(fade * 0.84 + floor(tile * 4.0) * 0.025 - step(0.77, band) * 0.11, 0.0, 1.0);
	vec3 rock = mix(shadow, stone, tone);
	float fissure = step(band, 0.12) * step(0.46, stone_hash(vec2(floor(cell.x * 1.9), floor(layer))));
	return mix(rock, vein, fissure * (0.11 + fade * 0.20));
}
