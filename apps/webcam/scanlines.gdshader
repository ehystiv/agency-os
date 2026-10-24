shader_type canvas_item;
// Righe di scansione della telecamera: una riga scura ogni tre pixel.

uniform float spacing = 3.0;
uniform float darkness = 0.3;

varying vec2 local_px;

void vertex() {
	local_px = VERTEX;
}

void fragment() {
	COLOR = vec4(0.0, 0.0, 0.0, mod(local_px.y, spacing) < 1.0 ? darkness : 0.0);
}
