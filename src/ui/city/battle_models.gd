class_name RomaBattleModels
extends RefCounted
## Original articulated geometry. UV2.x identifies rigid limbs, weapons and
## tack; battle_soldier.gdshader rotates those parts around matching joints.

static func oval(b: RealismModels, at: Vector3, size: Vector3, color: Color) -> void:
	var sphere := SphereMesh.new()
	sphere.radial_segments=12
	sphere.rings=6
	sphere.radius=1
	sphere.height=2
	b.add(sphere,at,size,color)

static func build(tint: Color, role: String, specialty: String) -> ArrayMesh:
	var b := RealismModels.new(true)
	var mounted := role=="cavalry"
	var commander := specialty=="commander"
	var elite := specialty!=""
	var archer := role=="archer"
	var spear := specialty=="spear_guard"
	var base := Vector3.UP*(1.05 if mounted else 0.0)
	var skin := RealismModels.pigment("#b18c72")
	var iron := RealismModels.pigment("#747d7b",0.82)
	var gold := RealismModels.pigment("#b69a61",0.72)
	var bronze := RealismModels.pigment("#9b855a" if commander else "#81765b",0.68)
	var leather := RealismModels.pigment("#382b22")
	var cloth := tint.darkened(0.15);cloth.a=0
	var linen := RealismModels.pigment("#c4b897")
	if mounted:_horse(b,cloth,commander)
	# Hip, layered tunic, cuirass, belt and hanging leather strips.
	b.part=0
	oval(b,base+Vector3(0,0.92,0),Vector3(0.20,0.17,0.14),cloth)
	oval(b,base+Vector3(0,1.19,0),Vector3(0.235,0.28,0.145),linen if archer else iron)
	for row in range(6):
		b.box(base+Vector3(0,1.07+row*0.059,-0.126),Vector3(0.40-row*0.014,0.044,0.045),bronze if commander else iron)
		for side in [-1,1]:
			b.box(base+Vector3(side*0.13,1.075+row*0.059,-0.154),Vector3(0.018,0.018,0.012),gold)
	for i in range(7):
		b.box(base+Vector3((i-3)*0.056,0.84,-0.145),Vector3(0.044,0.25,0.025),leather,Vector3(0,0,(i-3)*0.045))
	b.box(base+Vector3(0,0.99,-0.01),Vector3(0.44,0.066,0.30),leather)
	b.box(base+Vector3(0,0.99,-0.17),Vector3(0.07,0.058,0.025),gold)
	if elite:
		oval(b,base+Vector3(0,1.30,-0.173),Vector3(0.055,0.055,0.014),gold)
		for side in [-1,1]:
			b.box(base+Vector3(side*0.085,1.3,-0.161),Vector3(0.10,0.026,0.025),gold,Vector3(0,0,side*0.35))
	# Helmet and face remain rigid when the torso braces or turns.
	b.part=1
	b.rod(base+Vector3(0,1.39,0),base+Vector3(0,1.52,0),0.066,skin)
	oval(b,base+Vector3(0,1.60,-0.018),Vector3(0.107,0.143,0.103),skin)
	oval(b,base+Vector3(0,1.608,-0.12),Vector3(0.022,0.038,0.027),skin)
	b.box(base+Vector3(0,1.547,-0.105),Vector3(0.045,0.011,0.013),leather)
	oval(b,base+Vector3(0,1.696,0.006),Vector3(0.127,0.095,0.13),bronze)
	b.box(base+Vector3(0,1.656,-0.106),Vector3(0.24,0.025,0.072),bronze)
	b.box(base+Vector3(0,1.59,0.116),Vector3(0.23,0.065,0.06),bronze)
	for side in [-1,1]:
		b.box(base+Vector3(side*0.104,1.567,-0.021),Vector3(0.023,0.14,0.078),bronze,Vector3(0,0,side*0.10))
		b.box(base+Vector3(side*0.043,1.639,-0.112),Vector3(0.025,0.010,0.01),leather)
	if elite:
		oval(b,base+Vector3(0,1.794,0.0),Vector3(0.039,0.044,0.18),gold)
		for i in range(11):
			b.rod(base+Vector3(0,1.80,(i-5)*0.031),base+Vector3(0,1.97-abs(i-5)*0.014,(i-5)*0.039),0.023,RealismModels.pigment("#7e2924") if commander else cloth,0.014)
	# The two-segment arms and shield have separate hinge tags.
	for side in [-1.0,1.0]:
		b.part=2 if side>0 else 4
		oval(b,base+Vector3(side*0.25,1.35,0),Vector3(0.10,0.10,0.105),bronze if elite else cloth)
		b.rod(base+Vector3(side*0.26,1.34,0),base+Vector3(side*0.33,1.12,-0.07),0.066,skin)
		b.part=3 if side>0 else 5
		oval(b,base+Vector3(side*0.33,1.12,-0.07),Vector3.ONE*0.066,skin)
		b.rod(base+Vector3(side*0.33,1.12,-0.07),base+Vector3(side*0.34,1.18,-0.30),0.049,skin)
		oval(b,base+Vector3(side*0.34,1.18,-0.31),Vector3(0.049,0.058,0.06),skin)
	# Gladius has a forged point, fuller, grip, guard and pommel; it points
	# forward in guard so a shoulder/elbow thrust extends a coherent weapon.
	b.part=3
	if spear:
		b.rod(base+Vector3(0.34,1.16,0.8),base+Vector3(0.34,1.22,-1.55),0.019,leather)
		b.rod(base+Vector3(0.34,1.22,-1.55),base+Vector3(0.34,1.23,-1.91),0.04,iron,0)
	elif archer:
		for i in range(10):
			var a := Vector3(0.34,0.73+i*0.10,-0.30-sin(i*PI/10)*0.22)
			var c := Vector3(0.34,0.73+(i+1)*0.10,-0.30-sin((i+1)*PI/10)*0.22)
			b.rod(base+a,base+c,0.019,leather)
		b.rod(base+Vector3(0.34,0.73,-0.30),base+Vector3(0.34,1.73,-0.30),0.005,linen)
	else:
		b.rod(base+Vector3(0.34,1.18,-0.22),base+Vector3(0.34,1.18,-0.39),0.028,leather)
		oval(b,base+Vector3(0.34,1.18,-0.20),Vector3(0.044,0.044,0.034),bronze)
		b.box(base+Vector3(0.34,1.18,-0.39),Vector3(0.115,0.050,0.035),bronze)
		b.box(base+Vector3(0.34,1.18,-0.64),Vector3(0.055,0.018,0.49),iron)
		b.box(base+Vector3(0.34,1.192,-0.64),Vector3(0.010,0.008,0.41),iron.darkened(0.17))
		b.triangle(base+Vector3(0.311,1.19,-0.88),base+Vector3(0.369,1.19,-0.88),base+Vector3(0.34,1.19,-1.00),iron)
	b.part=5
	var small := mounted or archer
	oval(b,base+Vector3(-0.35,1.07,-0.35),Vector3(0.28,0.30 if small else 0.46,0.060),bronze)
	oval(b,base+Vector3(-0.35,1.07,-0.390),Vector3(0.257,0.278 if small else 0.431,0.027),cloth)
	oval(b,base+Vector3(-0.35,1.07,-0.425),Vector3(0.08,0.085,0.036),iron)
	if not archer:
		for side in [-1,1]:
			for end in [-1,1]:
				b.box(base+Vector3(-0.35+side*0.12,1.07+end*0.14,-0.42),Vector3(0.16,0.018,0.015),gold,Vector3(0,0,side*end*0.55))
	# Knees and ankles for foot soldiers; bent riding legs straddle the saddle.
	for side in [-1.0,1.0]:
		var hip := base+Vector3(side*0.12,0.91,0)
		var knee := base+Vector3(side*(0.40 if mounted else 0.13),0.54,-0.09)
		var ankle := base+Vector3(side*(0.43 if mounted else 0.13),0.13,0)
		b.part=6 if side<0 else 8
		b.rod(hip,knee,0.085,linen,0.095)
		b.part=7 if side<0 else 9
		oval(b,knee,Vector3.ONE*0.077,skin)
		b.rod(knee,ankle,0.057,skin,0.07)
		oval(b,ankle+Vector3(0,-0.058,-0.06),Vector3(0.080,0.062,0.15),leather)
		for strap in range(3):b.box(ankle+Vector3(0,strap*0.035,-0.065),Vector3(0.13,0.019,0.11),leather)
		if elite:oval(b,(knee+ankle)*0.5+Vector3(0,0,-0.047),Vector3(0.071,0.175,0.029),bronze)
	if elite:
		b.part=10
		for i in range(7):
			var x := (i-3)*0.066
			var top_left:=base+Vector3(x-0.034,1.43,0.14)
			var top_right:=base+Vector3(x+0.034,1.43,0.14)
			var hem_left:=base+Vector3(x*1.35-0.046,0.66,0.28+sin(i*1.2)*0.025)
			var hem_right:=base+Vector3(x*1.35+0.046,0.66,0.28+sin((i+1)*1.2)*0.025)
			b.triangle(top_left,top_right,hem_left,cloth)
			b.triangle(top_right,hem_right,hem_left,cloth)
	return b.finish()

static func _horse(b: RealismModels, cloth: Color, commander: bool) -> void:
	var coat := RealismModels.pigment("#4a342b" if commander else "#78604b")
	var dark := RealismModels.pigment("#27231f")
	var gold := RealismModels.pigment("#b29965",0.68)
	b.part=11
	oval(b,Vector3(0,1.10,0),Vector3(0.34,0.39,0.70),coat)
	oval(b,Vector3(0,1.47,-0.51),Vector3(0.23,0.48,0.28),coat)
	b.box(Vector3(0,1.41,0.05),Vector3(0.61,0.1,0.77),cloth)
	oval(b,Vector3(0,1.47,0.02),Vector3(0.27,0.09,0.30),dark)
	for side in [-1,1]:
		b.box(Vector3(side*0.337,1.21,0.02),Vector3(0.019,0.30,0.65),cloth)
		b.rod(Vector3(side*0.338,1.03,-0.30),Vector3(side*0.338,1.03,0.35),0.018,gold)
		for end in [-1,1]:
			b.part=12+(0 if side<0 else 2)+(0 if end<0 else 1)
			b.rod(Vector3(side*0.23,1.11,end*0.45),Vector3(side*0.23,0.55,end*0.45),0.077,coat,0.11)
			b.part+=6
			b.rod(Vector3(side*0.23,0.55,end*0.45),Vector3(side*0.23,0.12,end*0.47),0.050,coat,0.075)
			b.box(Vector3(side*0.23,0.08,end*0.47-0.035),Vector3(0.14,0.13,0.20),dark)
		b.part=11
	b.part=16
	b.rod(Vector3(0,1.26,0.58),Vector3(0,0.48,0.93),0.10,dark,0.035)
	b.part=17
	oval(b,Vector3(0,1.84,-0.80),Vector3(0.17,0.22,0.34),coat)
	oval(b,Vector3(0,1.76,-1.07),Vector3(0.16,0.13,0.13),dark)
	for side in [-1,1]:
		b.rod(Vector3(side*0.105,1.96,-0.68),Vector3(side*0.12,2.16,-0.64),0.046,coat,0.014)
		oval(b,Vector3(side*0.15,1.88,-0.86),Vector3(0.017,0.024,0.022),dark)
		b.rod(Vector3(side*0.16,1.92,-0.72),Vector3(side*0.16,1.68,-1.03),0.014,dark)
		b.rod(Vector3(side*0.17,1.70,-1.00),Vector3(side*0.22,1.67,-0.14),0.010,dark)
	b.box(Vector3(0,1.79,-1.085),Vector3(0.32,0.032,0.08),dark)
