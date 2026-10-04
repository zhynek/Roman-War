shader_type spatial;
render_mode diffuse_burley;
uniform vec4 pigment : source_color = vec4(0.5,0.4,0.27,1.0);
uniform float scale = 7.0;
uniform float grain = 0.18;
uniform int fabric = 0;
varying vec3 local;
float hash(vec3 p) { return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453); }
float noise(vec3 p) { vec3 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f); return mix(mix(mix(hash(i),hash(i+vec3(1,0,0)),f.x),mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z); }
void vertex() { local=VERTEX; }
void fragment() {
 float n=noise(local*scale)*0.65+noise(local*scale*4.0)*0.35;
 float mark=0.0;
 if(fabric==1) mark=sin(local.x*125.0+noise(local*2.0)*3.0)*0.06;
 if(fabric==2) mark=sin(local.y*155.0+noise(local*3.0)*2.0)*0.055;
 ALBEDO=pigment.rgb*(1.0+(n-0.5)*grain+mark);
 ROUGHNESS=0.94;
 NORMAL_MAP=vec3(0.5+(n-0.5)*0.15,0.5+(noise(local*scale+vec3(4.0))-0.5)*0.15,1.0);
}
