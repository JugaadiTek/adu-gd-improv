shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

// Animated flowing lava: two layers of scrolling value-noise, offset and
// blended, drive both the surface color gradient and an emissive pulse -
// the layering (different scroll directions/speeds + a distortion pass) is
// what sells "flowing", not just a single scrolling texture.

uniform vec3 color_dark : source_color = vec3(0.08, 0.01, 0.01);
uniform vec3 color_mid : source_color = vec3(0.55, 0.08, 0.02);
uniform vec3 color_hot : source_color = vec3(1.0, 0.55, 0.05);
uniform float scroll_speed : hint_range(0.0, 1.0) = 0.06;
uniform float noise_scale : hint_range(1.0, 40.0) = 8.0;
uniform float emission_strength : hint_range(0.0, 6.0) = 2.2;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.55;

// Cheap hash-based value noise (no texture lookup needed).
float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 uv) {
	vec2 i = floor(uv);
	vec2 f = fract(uv);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void fragment() {
	float t = TIME * scroll_speed;

	// Layer 1: slow broad flow.
	vec2 uv1 = UV * noise_scale + vec2(t * 1.3, t * 0.4);
	float n1 = value_noise(uv1);

	// Layer 2: faster, different direction - distorts layer 1 for a
	// "flowing/roiling" look instead of one mass sliding uniformly.
	vec2 uv2 = UV * noise_scale * 1.7 + vec2(-t * 2.1, t * 1.6);
	float n2 = value_noise(uv2);

	vec2 distorted = uv1 + (n2 - 0.5) * 0.6;
	float flow = value_noise(distorted);

	float heat = clamp(mix(n1, flow, 0.6), 0.0, 1.0);

	vec3 color = mix(color_dark, color_mid, smoothstep(0.15, 0.55, heat));
	color = mix(color, color_hot, smoothstep(0.6, 0.95, heat));

	ALBEDO = color;
	EMISSION = color * emission_strength * (0.5 + 0.5 * heat);
	ROUGHNESS = roughness_value;
}
