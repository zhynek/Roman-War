extends Control
## An original procedural portrait. Its speaking motion is presentation only.
var speaking: bool=false
var elapsed: float=0.0

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_process(false)

func set_speaking(active: bool) -> void:
	speaking=active
	set_process(active)
	queue_redraw()

func _process(delta: float) -> void:
	elapsed+=delta
	queue_redraw()

func _poly(points: Array,color: Color) -> void:
	draw_colored_polygon(PackedVector2Array(points),color)

func _draw() -> void:
	var edge: float=minf(size.x,size.y)
	if edge<=0:return
	draw_set_transform((size-Vector2.ONE*edge)*.5,0,Vector2.ONE*edge/100.0)
	var gold:=Color("c6b078")
	var hair:=Color("bcb8a4")
	var shade:=Color("878e80")
	var skin:=Color("c79f7b")
	draw_circle(Vector2(50,50),48,Color("172c2b"))
	draw_circle(Vector2(50,48),40,Color("2c4540"))
	draw_arc(Vector2(50,50),46,0,TAU,72,Color(gold,.7),1.2,true)
	_poly([Vector2(12,94),Vector2(20,75),Vector2(37,67),Vector2(62,67),Vector2(82,76),Vector2(91,94)],Color("d4ceae"))
	_poly([Vector2(12,94),Vector2(20,75),Vector2(36,70),Vector2(50,91),Vector2(66,97),Vector2(28,97)],Color("a6ad91"))
	_poly([Vector2(62,69),Vector2(81,77),Vector2(91,94),Vector2(70,96),Vector2(47,86)],Color("7c6450"))
	for i in range(4):
		draw_line(Vector2(23+i*6,78),Vector2(33+i*8,94),Color("e8dfba"),1,true)
	draw_circle(Vector2(76,79),4,gold)
	draw_circle(Vector2(76,79),2,Color("645e47"))
	_poly([Vector2(37,54),Vector2(63,54),Vector2(61,72),Vector2(49,78),Vector2(38,69)],skin.darkened(.17))
	draw_circle(Vector2(31,46),5,skin.darkened(.08))
	draw_circle(Vector2(68,46),5,skin.darkened(.24))
	_poly([Vector2(32,30),Vector2(42,23),Vector2(58,24),Vector2(68,32),Vector2(66,54),Vector2(59,67),Vector2(46,70),Vector2(34,56)],skin)
	_poly([Vector2(52,25),Vector2(66,32),Vector2(64,52),Vector2(57,65),Vector2(49,69),Vector2(54,53)],skin.darkened(.13))
	# Grey curls and a high, irregular hairline, never a copied likeness.
	for i in range(15):
		var angle: float=PI*.91+float(i)*PI*1.18/14.0
		var at:=Vector2(49,35)+Vector2(cos(angle)*21,sin(angle)*18)
		draw_circle(at,5.1,shade)
		draw_circle(at+Vector2(-.8,-1),3.8,hair)
	for side in [0,1]:
		for i in range(3):
			draw_circle(Vector2(31+side*37,36+i*5),3.5,shade)
	_poly([Vector2(33,49),Vector2(41,56),Vector2(48,58),Vector2(57,55),Vector2(65,48),Vector2(65,62),Vector2(58,75),Vector2(48,80),Vector2(37,70)],shade)
	for i in range(16):
		var row: int=i/4
		var x: float=37+float(i%4)*7+sin(float(i)*2.0)*1.5
		var y: float=58+float(row)*5
		draw_circle(Vector2(x,y),3.1,hair.lerp(shade,float(i%3)*.17))
	draw_line(Vector2(36,39),Vector2(45,38),shade,2,true)
	draw_line(Vector2(54,38),Vector2(63,40),shade,2,true)
	draw_line(Vector2(37,43),Vector2(44,43),Color("383d34"),1.5,true)
	draw_line(Vector2(55,43),Vector2(62,44),Color("383d34"),1.5,true)
	draw_circle(Vector2(41,42.7),.75,Color("e6e0c4"))
	draw_circle(Vector2(58,43),.65,Color("e6e0c4"))
	draw_line(Vector2(48,42),Vector2(46,52),skin.lightened(.15),1.5,true)
	draw_line(Vector2(46,53),Vector2(52,53),skin.darkened(.3),1,true)
	var mouth: float=1.0+(absf(sin(elapsed*9.0))*2.0 if speaking else 0.0)
	draw_ellipse_mouth(Vector2(49,61),mouth)
	for i in range(2):
		draw_line(Vector2(40,31+i*3),Vector2(57,31+i*3),Color(skin.darkened(.2),.6),.6,true)
	draw_line(Vector2(34,46),Vector2(39,48),skin.darkened(.25),.7,true)
	draw_line(Vector2(59,48),Vector2(64,46),skin.darkened(.25),.7,true)
	draw_set_transform(Vector2.ZERO,0,Vector2.ONE)

func draw_ellipse_mouth(at: Vector2,height: float) -> void:
	var points:=PackedVector2Array()
	for i in range(16):
		var angle: float=float(i)*TAU/16.0
		points.append(at+Vector2(cos(angle)*4.5,sin(angle)*height))
	draw_colored_polygon(points,Color("635a4d"))
