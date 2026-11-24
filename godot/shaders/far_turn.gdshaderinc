// A far column's turn from its lit top into its dark (the far rhythm waves and the plate behind them, set up in
// scripts/view/far_waves.gd): `x` of the way down the turn (0 where the lit top ends, 1 where the dark is reached) its
// brightness has turned smoothly that far, but its saturation is the dark's already halfway down — only the lit top is
// pale, the body shows its colour. Top and dark are the same hue, and so is every colour between.

float far_sat(vec3 c) {
	float hi = max(c.r, max(c.g, c.b));
	return hi > 0.0 ? (hi - min(c.r, min(c.g, c.b))) / hi : 0.0;
}

vec3 far_turn(vec3 top, vec3 low, float x) {
	vec3 c = mix(top, low, smoothstep(0.0, 1.0, x));
	float hi = max(c.r, max(c.g, c.b));
	float s = far_sat(c);
	float want = mix(far_sat(top), far_sat(low), smoothstep(0.0, 0.5, x));
	return s > 0.001 ? hi - (hi - c) * (want / s) : c;  // (as bright at its brightest, that saturated)
}
