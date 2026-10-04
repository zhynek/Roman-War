shader_type spatial;
render_mode cull_disabled;
varying vec3 wp;
void vertex(){ wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
float filtered_wave(float phase) {
  float footprint=length(vec2(dFdx(phase),dFdy(phase)));
  return sin(phase)*(1.0-smoothstep(1.0,3.0,footprint));
}
void fragment(){
  float a=filtered_wave(wp.x*0.071+wp.z*0.063+TIME*0.8);
  float b=filtered_wave(wp.x*0.19-wp.z*0.16-TIME*1.2);
  float c=filtered_wave(wp.x*0.39+wp.z*0.41+TIME*1.6);
  float distance_fade=1.0-smoothstep(800.0,4500.0,length(VERTEX));
  ALBEDO=mix(vec3(0.025,0.08,0.105),vec3(0.045,0.14,0.17),(a+b+2.0)*0.13*distance_fade);
  METALLIC=0.45; ROUGHNESS=0.28;
  // The sea PlaneMesh and generated basin meshes have different tangent data.
  // Both use one explicit world-space water normal instead of an absent TBN.
  vec3 water_normal=normalize(vec3((a*0.10+b*0.06)*distance_fade,1.0,(b*0.07+c*0.025)*distance_fade));
  NORMAL=normalize((VIEW_MATRIX*vec4(water_normal,0.0)).xyz);
}
