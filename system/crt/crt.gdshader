shader_type canvas_item;
// CRT monitor over everything: light scanlines, vignette and flicker,
// plus color split and horizontal tear during strong glitches.
// No curvature: clicks must land where the buttons are seen.

uniform sampler2D screen : hint_screen_texture, filter_linear;
uniform float scanline_alpha = 0.05;
uniform float vignette = 0.28;
uniform float flicker = 0.012;
// 0..1, raised for a moment by glitches.
uniform float aberration = 0.0;
uniform float tear = 0.0;

float noise(float x) {
	return fract(sin(x * 91.345) * 47453.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	if (tear > 0.0) {
		float band = floor(uv.y * 40.0 + floor(TIME * 20.0) * 3.0);
		uv.x += (noise(band) - 0.5) * 0.03 * tear * step(0.75, noise(band + 7.0));
	}
	vec2 shift = vec2(SCREEN_PIXEL_SIZE.x * 5.0 * aberration, 0.0);
	vec3 color = vec3(texture(screen, uv + shift).r, texture(screen, uv).g, texture(screen, uv - shift).b);
	float row = mod(FRAGCOORD.y, 3.0);
	color *= 1.0 - scanline_alpha * step(row, 1.0);
	vec2 centered = SCREEN_UV - 0.5;
	color *= 1.0 - vignette * dot(centered, centered) * 1.6;
	color *= 1.0 - flicker * noise(floor(TIME * 30.0));
	COLOR = vec4(color, 1.0);
}
