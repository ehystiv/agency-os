shader_type canvas_item;
// Camera scanlines: one dark line every three pixels.

uniform float spacing = 3.0;
uniform float darkness = 0.3;

varying vec2 local_px;

void vertex() {
	local_px = VERTEX;
}

void fragment() {
	COLOR = vec4(0.0, 0.0, 0.0, mod(local_px.y, spacing) < 1.0 ? darkness : 0.0);
}
