shader_type spatial;
render_mode diffuse_burley;
varying vec3 local;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void vertex(){local=VERTEX;}
void fragment(){
 float n=noise(local.xz*.7)*.6+noise(local.xz*13.0)*.4;
 float m=noise(local.xz*.13);
 vec3 grass=mix(vec3(.28,.34,.18),vec3(.42,.43,.28),m);
 vec3 earth=vec3(.43,.36,.25);
 float yard=1.0-smoothstep(23.0,43.0,length((local.xz-vec2(-6,3))*vec2(.95,1.0))+m*9.0);
 vec3 color=mix(grass,earth,yard);
 color=mix(vec3(.48,.45,.34),color,smoothstep(.45,1.3,local.y));
 color=mix(vec3(.25,.29,.23),color,smoothstep(-.2,.35,local.y));
 ALBEDO=color*(.89+n*.22);
 ROUGHNESS=.96;
 NORMAL_MAP=vec3(.5+(n-.5)*.2,.5+(noise(local.zx*11.0)-.5)*.2,1.0);
}
