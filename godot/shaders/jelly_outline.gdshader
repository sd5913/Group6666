shader_type spatial;
render_mode unshaded, cull_front;
// The player's outline: the jelly body pushed out a little along its normals, drawn from the inside in a darker shade.

#include "res://shaders/jelly.gdshaderinc"
#include "res://shaders/slime-shape.gdshaderinc"
uniform vec4 line : source_color = vec4(0.25, 0.15, 0.1, 1.0);
uniform float thickness = 0.05;

void vertex() {
	// Expand the original mesh before bending it, so the outline stays outside
	// the body even when a jump stretches the dome and its old normals tilt away.
	VERTEX += NORMAL * thickness;
	slime_shape(VERTEX);
}

void fragment() {
	ALBEDO = line.rgb;
}
