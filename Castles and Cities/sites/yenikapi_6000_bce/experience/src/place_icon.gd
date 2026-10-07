extends Control
## Original vector illustrations. No textures, font symbols or simulation state.
var kind: String="homes"
var accent: Color=Color("d5bc83")
func _ready() -> void:mouse_filter=Control.MOUSE_FILTER_IGNORE
func _draw() -> void:
	var scale_: float=minf(size.x/120.0,size.y/90.0)
	draw_set_transform((size-Vector2(120,90)*scale_)*.5,0,Vector2.ONE*scale_)
	draw_ellipse(Vector2(60,72),Vector2(44,11),Color("172c2c"))
	match kind:
		"homes","workroom","stores":
			poly([[24,43],[64,27],[99,43],[60,61]],Color("d7bc83"))
			poly([[24,43],[60,61],[60,80],[24,62]],Color("b39667"))
			poly([[60,61],[99,43],[99,62],[60,80]],Color("857857"))
			poly([[18,43],[58,13],[104,41],[61,63]],Color("c4965c"))
			poly([[18,43],[58,13],[61,39],[61,63]],Color("e2bb79"))
			for i in range(6):draw_line(Vector2(25+i*5,42-i*3),Vector2(60,58-i*3),Color("ac8957"),1.2,true)
			poly([[71,62],[82,57],[82,70],[71,76]],Color("263638"))
			if kind=="stores":
				for x in [25,37,49]:draw_ellipse(Vector2(x,67),Vector2(7,8),Color("bb8058"));draw_ellipse(Vector2(x,61),Vector2(6,3),Color("e1b580"))
			if kind=="workroom":
				draw_line(Vector2(17,69),Vector2(44,79),accent,5,true);draw_line(Vector2(19,62),Vector2(46,72),accent,5,true)
		"watch":
			for x in [30,66,90]:draw_line(Vector2(x,72),Vector2(x,32),Color("bc9161"),5,true)
			poly([[22,34],[56,17],[100,31],[66,49]],Color("d0aa70"))
			draw_line(Vector2(28,60),Vector2(89,43),accent,3,true)
			draw_circle(Vector2(65,51),4,Color("edce9e"));draw_line(Vector2(65,57),Vector2(65,70),Color("7a9e96"),6,true)
		"fields":
			poly([[13,58],[62,30],[109,54],[58,83]],Color("817451"))
			for x in range(4):
				for z in range(3):
					var v:=Vector2(28+x*15+z*7,59-x*8+z*6)
					draw_line(v,v+Vector2(0,-15),Color("dac47f"),2,true);draw_line(v+Vector2(0,-8),v+Vector2(-5,-13),accent,2,true);draw_line(v+Vector2(0,-7),v+Vector2(5,-12),accent,2,true)
		"landing":
			for i in range(4):draw_line(Vector2(13,49+i*8),Vector2(106,49+i*8),Color("689caa"),2,true)
			poly([[19,39],[75,30],[105,42],[79,59],[34,62]],Color("bc9867"))
			poly([[30,41],[75,36],[92,42],[76,51],[41,55]],Color("4b5548"))
			draw_line(Vector2(59,34),Vector2(32,76),accent,4,true)
		"yard","path":
			poly([[12,62],[70,28],[110,47],[51,84]],Color("8e9472"))
			poly([[36,77],[57,54],[92,41],[76,34],[43,48],[22,69]],Color("d4b98a"))
			for at in [Vector2(62,64),Vector2(78,54),Vector2(89,62)]:draw_circle(at,5,Color("bd9868"))
		"wood","blanks":
			for i in range(3):
				var y:float=45+i*12
				draw_line(Vector2(25,y+17),Vector2(93,y-10),Color("c69962"),11,true);draw_circle(Vector2(25,y+17),5,Color("e1c18b"))
			if kind=="blanks":draw_line(Vector2(53,43),Vector2(70,70),Color("627c75"),5,true)
		"people":
			for i in range(3):
				var x:float=29+i*30
				draw_circle(Vector2(x,31+abs(i-1)*8),8,Color("d5b083"));draw_line(Vector2(x,45+abs(i-1)*8),Vector2(x,71),Color("78a39b") if i==1 else accent,15,true)
		"kits":
			for i in range(3):draw_line(Vector2(32+i*14,77),Vector2(52+i*14,19),accent,5,true)
			draw_line(Vector2(41,48),Vector2(77,59),Color("71938a"),5,true)
		"food":
			draw_ellipse(Vector2(60,61),Vector2(28,18),Color("bb8455"));draw_ellipse(Vector2(60,53),Vector2(28,12),accent)
			for i in range(8):draw_circle(Vector2(43+(i%4)*11,50+(i/4)*7),3,Color("e4d49e"))
		"guide","growth":
			for x in [25,60,95]:draw_line(Vector2(60,27),Vector2(x,63),Color("8eae9f"),3,true);draw_circle(Vector2(x,66),10,accent)
			draw_circle(Vector2(60,25),12,Color("6da398"))
		"warning":
			poly([[60,12],[106,77],[14,77]],Color("d4a665"));draw_line(Vector2(60,32),Vector2(60,55),Color("253536"),5,true);draw_circle(Vector2(60,66),3,Color("253536"))
		_:
			draw_arc(Vector2(60,45),25,0,TAU,40,accent,3,true);draw_line(Vector2(60,27),Vector2(60,50),accent,3,true);draw_line(Vector2(60,50),Vector2(75,58),accent,3,true)
func poly(points: Array,color: Color) -> void:
	var p:=PackedVector2Array()
	for v in points:p.append(Vector2(v[0],v[1]))
	draw_colored_polygon(p,color)
func draw_ellipse(at: Vector2,radius: Vector2,color: Color) -> void:
	var points:=PackedVector2Array()
	for i in range(40):points.append(at+Vector2(cos(i*TAU/40),sin(i*TAU/40))*radius)
	draw_colored_polygon(points,color)
