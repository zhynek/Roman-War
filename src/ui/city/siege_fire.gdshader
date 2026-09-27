shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform float clock_time = 0.0;
uniform bool smoke = false;
varying vec2 uv;
float hash(vec2 p) {return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p) {vec2 i=floor(p);vec2 f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
void vertex(){
	uv=UV;
	MODELVIEW_MATRIX=VIEW_MATRIX*mat4(INV_VIEW_MATRIX[0],INV_VIEW_MATRIX[1],INV_VIEW_MATRIX[2],MODEL_MATRIX[3]);
}
void fragment(){
	float y=1.0-uv.y;
	float n=noise(vec2(uv.x*6.0,y*4.0-clock_time*2.8));
	float fine=noise(vec2(uv.x*17.0,y*11.0-clock_time*4.0));
	float drift=sin(y*7.0-clock_time*2.0)*0.07*y;
	float width=(1.0-y)*0.39+0.035;
	float shape=1.0-smoothstep(width*0.35,width,abs(uv.x-0.5+drift)+(n-0.5)*0.20);
	float flame=shape*smoothstep(0.0,0.13,y)*(1.0-smoothstep(0.6,1.0,y))*(0.65+fine*0.35);
	if(smoke){
		float cloud=noise(vec2(uv.x*4.0,y*5.0-clock_time*0.5));
		float edge=1.0-smoothstep(0.15,0.5,length(vec2((uv.x-0.5)*1.25,(y-0.5)*0.85)));
		ALBEDO=mix(vec3(0.055,0.05,0.043),vec3(0.22,0.20,0.17),cloud);
		ALPHA=edge*cloud*0.65;
	}else{
		vec3 hot=mix(vec3(1.0,0.75,0.20),vec3(0.8,0.055,0.004),smoothstep(0.1,0.8,y));
		ALBEDO=hot;EMISSION=hot*2.5;ALPHA=flame;
	}
}
