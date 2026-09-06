shader_type spatial;
render_mode cull_disabled, diffuse_burley;
uniform float clock_time = 0.0;
varying vec4 tint;
void vertex() {
 tint=COLOR;
 vec3 origin=MODEL_MATRIX[3].xyz;
 VERTEX.x += sin(clock_time*0.85+origin.x*0.3+VERTEX.y)*0.07*max(VERTEX.y-2.0,0.0);
}
void fragment() {
 ALBEDO=pow(tint.rgb,vec3(2.2));
 ROUGHNESS=0.96;
 BACKLIGHT=pow(tint.rgb,vec3(2.2))*0.55;
}
