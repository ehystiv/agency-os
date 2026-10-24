shader_type canvas_item;
// Effects over what is already drawn: 0 = color split, 1 = inversion, 2 = static noise.

uniform int mode = 0;
uniform float strength = 1.0;
uniform sampler2D screen : hint_screen_texture, filter_nearest;

float noise(vec2 cell) {
	return fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	if (mode == 0) {
		float d = strength * SCREEN_PIXEL_SIZE.x * 4.0 * sign(sin(TIME * 23.0));
		vec2 uv = SCREEN_UV;
		COLOR = vec4(texture(screen, uv + vec2(d, 0.0)).r, texture(screen, uv).g, texture(screen, uv - vec2(d, 0.0)).b, 1.0);
	} else if (mode == 1) {
		// Like the prototype's invert(1) hue-rotate(180deg): inverted lightness, hue kept.
		vec3 c = texture(screen, SCREEN_UV).rgb;
		float luma = dot(c, vec3(0.299, 0.587, 0.114));
		COLOR = vec4(clamp(c + 1.0 - 2.0 * luma, 0.0, 1.0), 1.0);
	} else {
		float n = noise(floor(UV * vec2(160.0, 100.0)) + floor(TIME * 18.0) * 7.0);
		COLOR = vec4(n * 0.6, n, n, strength);
	}
}
