shader_type spatial;
render_mode cull_disabled;
varying vec3 wp;
void vertex(){ wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment(){
  float a=sin(wp.x*0.071+wp.z*0.063+TIME*0.8);
  float b=sin(wp.x*0.19-wp.z*0.16-TIME*1.2);
  float c=sin(wp.x*0.39+wp.z*0.41+TIME*1.6);
  float distance_fade=1.0-smoothstep(800.0,4500.0,length(VERTEX));
  ALBEDO=mix(vec3(0.025,0.08,0.105),vec3(0.045,0.14,0.17),(a+b+2.0)*0.13*distance_fade);
  METALLIC=0.45; ROUGHNESS=0.28;
  NORMAL_MAP=vec3(0.5+(a*0.10+b*0.06)*distance_fade,0.5+(b*0.07+c*0.025)*distance_fade,1.0);
  NORMAL_MAP_DEPTH=0.5;
}
