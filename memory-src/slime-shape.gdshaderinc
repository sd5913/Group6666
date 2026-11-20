// Reshape only the render mesh. The original jelly deformation still follows
// the player's squash, crouch and lean uniforms with the same foot pivot.
float slime_height(vec3 v) {
	return clamp((v.y - feet) / tall, 0.0, 1.0);
}

void slime_shape(inout vec3 v) {
	float h = slime_height(v);
	float dome = mix(1.42, 0.68, pow(h, 2.8));
	v.xz *= dome;
	v.y = feet + (v.y - feet) * 0.67;
	jelly(v);
}
