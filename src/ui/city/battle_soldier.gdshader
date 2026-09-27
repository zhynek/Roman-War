shader_type spatial;
render_mode cull_disabled;
uniform float clock_time = 0.0;
uniform float walking = 0.0;
uniform float fighting = 0.0;
uniform float hit_reaction = 0.0;
uniform float shooting = 0.0;
uniform float attack_age = 100.0;
uniform float defend_age = 100.0;
uniform float mounted = 0.0;
uniform float archer = 0.0;
uniform float spear = 0.0;
uniform float bracing = 0.0;
varying vec4 pigment;
varying vec3 surface_point;

mat3 rx(float a) { return mat3(vec3(1.,0.,0.),vec3(0.,cos(a),sin(a)),vec3(0.,-sin(a),cos(a))); }
mat3 ry(float a) { return mat3(vec3(cos(a),0.,-sin(a)),vec3(0.,1.,0.),vec3(sin(a),0.,cos(a))); }
mat3 rz(float a) { return mat3(vec3(cos(a),sin(a),0.),vec3(-sin(a),cos(a),0.),vec3(0.,0.,1.)); }
float pulse(float t, float start, float peak, float hold, float end) {
	return smoothstep(start,peak,t)*(1.-smoothstep(hold,end,t));
}

void vertex() {
	pigment=COLOR;
	surface_point=VERTEX;
	float seed=INSTANCE_CUSTOM.r;
	float front=INSTANCE_CUSTOM.g;
	float part=floor(UV2.x+0.5);
	float phase=clock_time*7.0+seed*6.283185;
	float a=attack_age-seed*0.10;
	float wind=pulse(a,0.,0.12,0.14,0.32)*front;
	float strike=pulse(a,0.12,0.31,0.35,0.72)*front;
	float block=pulse(defend_age,0.02,0.19,0.35,0.65)*front;
	float cut=step(0.52,seed)*(1.-spear);
	float guard=max(fighting*0.4,bracing);
	vec3 base=vec3(0.,mounted*1.05,0.);
	vec3 p=VERTEX;
	vec3 n=NORMAL;
	mat3 bend=mat3(1.);
	vec3 pivot=vec3(0.);
	// Forearms rotate at elbows before the entire arm rotates at its shoulder.
	if (part==3. || part==5.) {
		float right=part==3.?1.:-1.;
		pivot=base+vec3(right*0.33,1.12,-0.07);
		float rest=(1.-archer)*(1.-spear)*(1.-strike)*0.85;
		float elbow=part==3.?rest+wind*0.55-strike*0.68+shooting*0.45:guard*0.12+block*0.18;
		bend=rx(elbow);
		p=pivot+bend*(p-pivot);n=bend*n;
	}
	if (part>=2. && part<=5.) {
		float right=part<=3.?1.:-1.;
		pivot=base+vec3(right*0.26,1.34,0.);
		if (right>0.) {
			bend=ry(cut*(-wind*0.65+strike*0.45))*rz(cut*(-wind*0.35+strike*0.25))*rx(-wind*(0.40+cut*0.5)+strike*0.95+guard*0.12);
		} else {
			bend=ry(-guard*0.10-block*0.16)*rx(guard*0.18+block*0.5);
		}
		p=pivot+bend*(p-pivot);n=bend*n;
	}
	if (part>=6. && part<=9. && mounted<0.5) {
		float side=part<8.?-1.:1.;
		float step_phase=phase+(side>0.?3.14159:0.);
		if (part==7. || part==9.) {
			pivot=vec3(side*0.13,0.54,-0.09);
			bend=rx(-max(0.,sin(step_phase))*walking*0.72);
			p=pivot+bend*(p-pivot);n=bend*n;
		}
		pivot=vec3(side*0.12,0.91,0.);
		bend=rx(sin(step_phase)*walking*0.48+(side<0.?strike*0.14:-strike*0.12));
		p=pivot+bend*(p-pivot);n=bend*n;
	}
	if (part==1.) {
		pivot=base+vec3(0.,1.44,0.);
		bend=ry(sin(clock_time*1.1+seed*6.28)*0.045*(1.-fighting));
		p=pivot+bend*(p-pivot);n=bend*n;
	}
	if (part==10.) {
		p.z+=sin(clock_time*4.+p.x*9.)*0.065*clamp(1.43-(p.y-base.y),0.,1.)*(0.25+walking);
	}
	if (part<6. || part==10.) {
		pivot=base+vec3(0.,0.93,0.);
		bend=ry(wind*0.16-strike*0.19)*rx(-strike*0.12+hit_reaction*0.18-bracing*0.08);
		p=pivot+bend*(p-pivot);n=bend*n;
		p.z-=strike*0.09;
	}
	if ((part>=12. && part<=15.) || (part>=18. && part<=21.)) {
		float leg=part>=18.?part-6.:part;
		float side=leg<14.?-1.:1.;
		float end=mod(leg,2.)<0.5?-1.:1.;
		float hoof_phase=phase+(side*end>0.?3.14159:0.);
		if (part>=18.) {
			pivot=vec3(side*0.23,0.55,end*0.45);
			bend=rx(-max(0.,sin(hoof_phase))*walking*0.60);
			p=pivot+bend*(p-pivot);n=bend*n;
		}
		pivot=vec3(side*0.23,1.11,end*0.45);
		bend=rx(sin(hoof_phase)*walking*0.50);
		p=pivot+bend*(p-pivot);n=bend*n;
	}
	if (part==16.) {
		pivot=vec3(0.,1.26,0.58);bend=rz(sin(phase*0.4)*0.12);
		p=pivot+bend*(p-pivot);n=bend*n;
	}
	if (part==17.) {
		pivot=vec3(0.,1.5,-0.5);bend=rx(sin(phase*2.)*walking*0.035);
		p=pivot+bend*(p-pivot);n=bend*n;
	}
	p.y+=sin(phase*2.)*0.019*walking;
	VERTEX=p;
	NORMAL=normalize(n);
}

void fragment() {
	// Fine forged-metal scratches and uneven cloth/leather break the plastic
	// sheen without image textures or scene-dependent random draws.
	float grain=fract(sin(dot(floor(surface_point*180.),vec3(12.9898,78.233,39.425)))*43758.5453);
	float scratches=smoothstep(0.90,1.,sin(surface_point.y*410.+sin(surface_point.x*125.)*2.));
	ALBEDO=pow(pigment.rgb,vec3(2.2))*(0.88+grain*0.16+scratches*pigment.a*0.08);
	METALLIC=pigment.a;
	ROUGHNESS=mix(0.88,0.48,pigment.a)+(grain-0.5)*0.10;
	SPECULAR=0.28;
}
