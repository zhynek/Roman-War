shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
// Original procedural surface: alpha is a material tag, never transparency.
// Skin .10; cloth .30; hair .50; leather .65; ceramic .72; bronze .82; iron .90.
varying vec3 model_position;
varying vec3 model_normal;

float grain(vec3 p) {
	return fract(sin(dot(floor(p), vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

void vertex() {
	model_position = VERTEX;
	model_normal = NORMAL;
}

void fragment() {
	vec3 base = pow(max(COLOR.rgb, vec3(0.0)), vec3(2.2));
	float kind = COLOR.a;
	float cloth = float(kind > 0.20 && kind < 0.41);
	float skin = float(kind < 0.20);
	float hair = float(kind > 0.42 && kind < 0.58);
	float metal = float(kind > 0.77 && kind < 0.96);
	vec3 p = model_position;
	vec3 n = abs(normalize(model_normal));
	vec2 weave_uv = n.z > n.x ? p.xy : p.zy;
	float weave_scale = 165.0;
	float weave_filter = 1.0 - smoothstep(0.3, 1.1, max(fwidth(weave_uv.x), fwidth(weave_uv.y)) * weave_scale);
	float weave = sin(weave_uv.x * weave_scale * 6.2831853) * sin(weave_uv.y * weave_scale * 6.2831853);
	float fiber = grain(p * 560.0) - 0.5;
	float broad = sin(p.x * 31.7 + p.y * 11.0) * sin(p.z * 27.1 + p.y * 24.0);
	base *= 1.0 + cloth * (weave * weave_filter * 0.035 + broad * 0.035);
	base *= 1.0 + skin * (fiber * weave_filter * 0.035 + broad * 0.018);
	base *= 1.0 + hair * (sin(p.y * 290.0 + p.x * 41.0) * 0.075 + fiber * 0.09);
	base *= 1.0 + metal * (fiber * 0.08 + broad * 0.08);
	ALBEDO = base;
	ROUGHNESS = 0.75 + cloth * 0.20 - skin * 0.16 - metal * 0.35 + hair * 0.05;
	METALLIC = metal * 0.73;
	SPECULAR = 0.28 + metal * 0.22;
}
