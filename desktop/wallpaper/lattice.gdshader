shader_type canvas_item;
// Reticolo triangolare del prototipo: righe a 60°, -60° e 0°, sottili e trasparenti.

uniform vec4 desk_color : source_color = vec4(0.039, 0.055, 0.110, 1.0);
uniform vec4 line_color : source_color = vec4(0.471, 0.667, 0.863, 0.07);
uniform float diagonal_spacing = 46.0;
uniform float horizontal_spacing = 40.0;
// 0..1: il reticolo della gabbia che pulsa (glitch "reticolo").
uniform float pulse = 0.0;
uniform vec4 pulse_color : source_color = vec4(0.498, 0.882, 0.933, 0.22);

varying vec2 local_px;

void vertex() {
	local_px = VERTEX;
}

float line_at(float d, float spacing) {
	return step(mod(d, spacing), 1.0);
}

void fragment() {
	vec2 p = local_px;
	float s60 = 0.8660254;
	float lines = max(
		max(line_at(dot(p, vec2(s60, -0.5)) + 10000.0, diagonal_spacing),
			line_at(dot(p, vec2(-s60, -0.5)) + 10000.0, diagonal_spacing)),
		line_at(-p.y + 10000.0, horizontal_spacing));
	float diagonals = max(line_at(dot(p, vec2(s60, -0.5)) + 10000.0, diagonal_spacing),
		line_at(dot(p, vec2(-s60, -0.5)) + 10000.0, diagonal_spacing));
	vec3 color = mix(desk_color.rgb, line_color.rgb, lines * line_color.a);
	COLOR = vec4(mix(color, pulse_color.rgb, diagonals * pulse_color.a * pulse), 1.0);
}
