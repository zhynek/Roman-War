shader_type spatial;
render_mode cull_disabled, diffuse_burley;
varying vec4 tint;
void vertex() { tint = COLOR; }
void fragment() {
 ALBEDO = pow(tint.rgb, vec3(2.2));
 ROUGHNESS = 0.9;
}
