shader_type spatial;
render_mode cull_disabled;
uniform float clock_time = 0.0;
uniform float walking = 0.0;
varying vec4 tint;
void vertex() {
 tint=COLOR;
 float phase=clock_time*7.0+INSTANCE_CUSTOM.r*6.283;
 if(VERTEX.y<0.85) {
  float leg=VERTEX.x>0.0?1.0:-1.0;
  VERTEX.z+=sin(phase)*0.19*leg*(1.0-VERTEX.y/0.85)*walking;
  VERTEX.y+=max(0.0,cos(phase)*leg)*0.09*(1.0-VERTEX.y/0.85)*walking;
 }
 VERTEX.y+=sin(phase*2.0)*0.018*walking;
 if(VERTEX.z>0.16 && VERTEX.y>0.9) { VERTEX.z+=sin(phase+VERTEX.y*6.0)*0.025*walking; }
}
void fragment() {
 ALBEDO=pow(tint.rgb,vec3(2.2));
 METALLIC=tint.a;
 ROUGHNESS=mix(0.88,0.36,tint.a);
}
