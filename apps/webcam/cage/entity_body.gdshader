shader_type spatial;
// The Entity's mass: a sphere deformed by overlapping waves (the prototype's formula),
// with flat faces. The same formula is in entity_model.gd to attach eyes and tentacles.

uniform vec3 albedo : source_color = vec3(0.031, 0.075, 0.11);
uniform vec3 emission_calm : source_color = vec3(0.012, 0.078, 0.102);
uniform vec3 emission_red : source_color = vec3(0.227, 0.024, 0.027);
uniform float tint = 0.0;
// Deformation amplitude and wave time.
uniform float amount = 0.12;
uniform float wave_time = 0.0;

float wave(vec3 p, float t) {
	return sin(p.x * 3.0 + t * 1.1) * 0.5
		+ sin(p.y * 4.3 - t * 0.9) * 0.35
		+ sin(p.z * 5.1 + t * 1.7 + p.x * 2.0) * 0.25;
}

void vertex() {
	VERTEX *= 1.0 + wave(VERTEX, wave_time) * amount;
}

void fragment() {
	// Per-face normal: low-poly look even with the deformation.
	// The cross product order follows Godot's screen y axis.
	NORMAL = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	ALBEDO = albedo;
	ROUGHNESS = 0.3;
	SPECULAR = 0.7;
	EMISSION = mix(emission_calm, emission_red, tint);
}
