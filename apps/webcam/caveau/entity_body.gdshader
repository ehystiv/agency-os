shader_type spatial;
// Massa dell'Entità: sfera deformata da onde sovrapposte (formula del prototipo),
// a facce piatte. La stessa formula è in entity.gd per agganciare occhi e tentacoli.

uniform vec3 albedo : source_color = vec3(0.031, 0.075, 0.11);
uniform vec3 emission_calm : source_color = vec3(0.012, 0.078, 0.102);
uniform vec3 emission_red : source_color = vec3(0.227, 0.024, 0.027);
uniform float tint = 0.0;
// Ampiezza della deformazione e tempo dell'onda.
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
	// Normale per faccia: aspetto low-poly anche con la deformazione.
	// L'ordine del prodotto vettoriale segue l'asse y dello schermo di Godot.
	NORMAL = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	ALBEDO = albedo;
	ROUGHNESS = 0.3;
	SPECULAR = 0.7;
	EMISSION = mix(emission_calm, emission_red, tint);
}
