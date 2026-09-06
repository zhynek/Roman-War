shader_type spatial;
render_mode diffuse_burley;
uniform float clock_time = 0.0;
varying vec3 world;
void vertex() { world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
 float a=sin(world.x*2.1+world.z*1.4+clock_time*0.8);
 float b=sin(world.z*3.7-world.x*0.9+clock_time*1.1);
 float c=sin(world.x*11.0+world.z*8.0+clock_time*1.3);
 ALBEDO=mix(vec3(0.052,0.14,0.145),vec3(0.14,0.26,0.24),a*0.17+b*0.1+0.45);
 ALBEDO=pow(ALBEDO,vec3(1.6));
 ROUGHNESS=0.25; METALLIC=0.30; SPECULAR=0.8;
 NORMAL_MAP=normalize(vec3(a*0.022+c*0.018,b*0.026,1.0))*0.5+0.5;
 NORMAL_MAP_DEPTH=0.6;
}
