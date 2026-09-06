shader_type spatial;
render_mode cull_disabled;
uniform vec4 ground_color : source_color = vec4(0.42, 0.48, 0.28, 1.0);
uniform bool marsh = false;
uniform bool world_uv = false;
varying float height;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
 vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void vertex() { height=VERTEX.y; if (world_uv) { UV=VERTEX.xz; } }
void fragment() {
 float grain=noise(UV*5.0)*0.5+noise(UV*17.0)*0.3+noise(UV*43.0)*0.2;
 float field=noise(UV*0.16);
 vec3 soil=ground_color.rgb*(0.68+field*0.35+grain*0.4);
 float rock=smoothstep(6.0,21.0,height);
 soil=mix(soil,vec3(0.33,0.34,0.30)*(0.7+grain*0.6),rock);
 soil=mix(soil,vec3(0.73,0.74,0.69),smoothstep(28.0,44.0,height)*0.7);
 float wet=marsh? smoothstep(0.34,0.62,noise(UV*0.22)):0.0;
 ALBEDO=pow(mix(soil,vec3(0.055,0.13,0.13)*(0.7+grain*0.6),wet),vec3(2.2));
 ROUGHNESS=mix(0.92,0.26,wet);
 METALLIC=wet*0.28;
 NORMAL_MAP=normalize(vec3((noise(UV*9.0)-0.5)*0.25,(noise(UV*9.0+7.0)-0.5)*0.25,1.0))*0.5+0.5;
}
