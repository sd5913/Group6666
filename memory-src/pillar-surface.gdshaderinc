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
