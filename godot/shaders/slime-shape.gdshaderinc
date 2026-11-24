// Reshape only the render mesh. The original jelly deformation still follows
// the player's squash, crouch and lean uniforms with the same foot pivot.
float slime_height(vec3 v) {
	return clamp((v.y - feet) / tall, 0.0, 1.0);
}

void slime_shape(inout vec3 v) {
	float h = slime_height(v);
	// The tavern guest has broad, almost straight sides below a rounded dome.
	float crown = max(0.0, (h - 0.35) / 0.69);
	float dome = h < 0.35 ? mix(1.48, 1.56, h / 0.35) : 1.56 * sqrt(max(0.0, 1.0 - crown * crown));
	v.xz *= dome;
	v.y = feet + (v.y - feet) * 0.67;
	jelly(v);
}
