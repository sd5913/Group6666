// Integer art cells keep the backdrop on the same grid as the runner.
float cavern_hash(float n) {
	return fract(n * 0.6180339887);
}

vec3 cavern_wall(vec2 art) {
	float section = floor(art.x / 53.0);
	float seed = cavern_hash(section + 3.0);
	float u = mod(art.x, 53.0);
	float needle = max(0.0, 1.0 - abs(u - (15.0 + 20.0 * seed)) / (5.0 + 10.0 * seed));
	float rock = 4.0 * sin(art.x / 29.0) + 2.0 * sin(art.x / 9.0);
	float roof = 15.0 + 3.0 * floor((rock + (9.0 + 23.0 * seed) * needle) / 3.0);
	float ridge = 51.0 + 3.0 * floor((12.0 * sin(art.x / 34.0) + 8.0 * sin(art.x / 17.0)) / 3.0);
	vec3 color = vec3(0.16, 0.12, 0.23);
	if (art.y < ridge) {
		color = vec3(0.21, 0.14, 0.27);
	}
	if (art.y < roof + 4.0) {
		color = art.y < roof ? vec3(0.13, 0.09, 0.16) : vec3(0.31, 0.15, 0.29);
	}
	vec2 tile = floor(art / vec2(13.0, 11.0));
	float fleck = cavern_hash(tile.x * 37.0 + tile.y * 113.0);
	vec2 dot_at = vec2(2.0 + floor(fleck * 8.0), 2.0 + floor(fract(fleck * 13.0) * 7.0));
	if (fleck > 0.71 && all(lessThan(abs(mod(art, vec2(13.0, 11.0)) - dot_at), vec2(1.0)))) {
		color += vec3(0.075, 0.047, 0.077);
	}
	return color;
}

vec3 cavern_grade(vec3 color, vec2 art) {
	float low = min(color.r, min(color.g, color.b));
	float high = max(color.r, max(color.g, color.b));
	float brightness = dot(color, vec3(0.299, 0.587, 0.114));
	// Only the original warm sky, not the new blue-pink platform faces.
	if (art.y < 112.0 && color.r > 0.74 && color.g > 0.69 && low > 0.61
			&& color.g - color.b > 0.025 && high - low < 0.25) {
		return cavern_wall(art);
	}
	if (color.r - color.b > 0.15 && color.r >= color.g && color.g >= color.b) {
		vec3 shade = mix(vec3(0.17, 0.09, 0.20), vec3(0.94, 0.54, 0.68), brightness);
		return mix(shade, vec3(0.99, 0.73, 0.78), smoothstep(0.63, 0.96, brightness) * 0.64);
	}
	return color;
}
