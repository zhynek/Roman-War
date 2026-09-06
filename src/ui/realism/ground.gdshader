shader_type spatial;
render_mode diffuse_burley;
varying vec3 world_pos;
varying vec3 ground_normal;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
 vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz; ground_normal = NORMAL; }
void fragment() {
 vec2 p = world_pos.xz;
 float broad=noise(p*0.2), fine=noise(p*7.0), grit=noise(p*35.0);
 vec3 grass=mix(vec3(0.20,0.245,0.12),vec3(0.37,0.385,0.22),broad);
 grass=mix(grass,vec3(0.38,0.34,0.22),smoothstep(0.55,0.8,noise(p*0.8))*0.6);
 float slope=1.0-ground_normal.y;
 float rock=smoothstep(0.11,0.34,slope) + smoothstep(8.0,18.0,world_pos.y)*0.7;
 vec3 stone=mix(vec3(0.23,0.25,0.24),vec3(0.52,0.51,0.45),noise(p*1.7));
 stone *= 0.94+0.055*sin(world_pos.y*3.2+noise(p)*3.0);
 vec3 col=mix(grass,stone,clamp(rock,0.0,1.0));
 float wet=1.0-smoothstep(0.85,1.8,world_pos.y);
 col=mix(col,vec3(0.13,0.145,0.09),wet*0.65);
 col *= 0.78 + fine*0.28 + grit*0.14;
 ALBEDO=pow(col,vec3(1.8)); ROUGHNESS=mix(0.94,0.48,wet);
 NORMAL_MAP=normalize(vec3((fine-grit)*0.30,(noise(p*7.0+vec2(5.0))-fine)*0.30,1.0))*0.5+0.5;
 NORMAL_MAP_DEPTH=0.18;
}
