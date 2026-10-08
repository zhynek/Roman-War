extends RefCounted
## Immutable integer grid, captured from the actual village's collision surface.
## Conservative cells contain the whole small group's footprint. No scene access.
static func point(a: Array) -> Vector2:return Vector2(a[0],a[1])
static func packed(p: Vector2) -> Array:return [roundi(p.x),roundi(p.y)]
static func cell(nav: Dictionary,p: Array) -> Vector2i:
	return Vector2i(roundi(float(p[0]-nav.origin[0])/nav.cell),roundi(float(p[1]-nav.origin[1])/nav.cell))
static func at(nav: Dictionary,c: Vector2i) -> Array:return [int(nav.origin[0])+c.x*int(nav.cell),int(nav.origin[1])+c.y*int(nav.cell)]
static func clear_cell(nav: Dictionary,c: Vector2i) -> bool:
	return c.x>=0 and c.y>=0 and c.x<int(nav.width) and c.y<int(nav.height) and nav.rows[c.y][c.x]=="."
static func clear(nav: Dictionary,p: Array) -> bool:return clear_cell(nav,cell(nav,p))
static func nearest(nav: Dictionary,p: Array) -> Array:
	var start:=cell(nav,p)
	for radius in range(maxi(int(nav.width),int(nav.height))):
		for y in range(start.y-radius,start.y+radius+1):
			for x in range(start.x-radius,start.x+radius+1):
				if radius>0 and abs(x-start.x)!=radius and abs(y-start.y)!=radius:continue
				if clear_cell(nav,Vector2i(x,y)):return at(nav,Vector2i(x,y))
	return []
static func route(nav: Dictionary,from: Array,to: Array) -> Array:
	var start:=cell(nav,from);var end:=cell(nav,to)
	if not clear_cell(nav,start) or not clear_cell(nav,end):return []
	if start==end:return [at(nav,end)]
	var queue: Array[Vector2i]=[start]
	var came: Dictionary={start:start}
	var i: int=0
	while i<queue.size():
		var c: Vector2i=queue[i];i+=1
		for delta in [Vector2i(0,-1),Vector2i(-1,0),Vector2i(1,0),Vector2i(0,1)]:
			var n: Vector2i=c+delta
			if came.has(n) or not clear_cell(nav,n):continue
			came[n]=c
			if n==end:
				var path: Array=[];var cursor:=end
				while cursor!=start:path.push_front(at(nav,cursor));cursor=came[cursor]
				# Return to the current cell's center only if off its axis; this
				# keeps turns inside safe cells without pulling pursuit backwards.
				var center: Array=at(nav,start)
				if from!=center and from[0]!=path[0][0] and from[1]!=path[0][1]:path.push_front(center)
				return path
			queue.append(n)
	return []
static func line(nav: Dictionary,a: Array,b: Array) -> bool:
	var p:=point(a);var q:=point(b)
	var steps: int=maxi(1,ceili(p.distance_to(q)/(float(nav.cell)*.25)))
	for i in range(steps+1):
		if not clear(nav,packed(p.lerp(q,float(i)/steps))):return false
	return true
static func valid(nav: Variant,r) -> bool:
	if not nav is Dictionary or nav.size()!=7:return false
	for k in ["width","height","cell"]:
		if not r.whole(nav.get(k),1,300):return false
	if not position(nav.get("origin"),r) or not nav.get("signature") is String:return false
	if not nav.get("rows") is Array or nav.rows.size()!=int(nav.height):return false
	for row in nav.rows:
		if not row is String or row.length()!=int(nav.width):return false
		for c in row:
			if c not in [".","#"]:return false
	if nav.signature!=JSON.stringify(nav.rows).sha256_text():return false
	if not nav.get("places") is Dictionary or nav.places.size()!=4:return false
	for id in ["stores","north","landing","refuge"]:
		if not position(nav.places.get(id),r) or not clear(nav,nav.places[id]):return false
	return true
static func position(p: Variant,r) -> bool:
	return p is Array and p.size()==2 and r.whole(p[0],-30000,30000) and r.whole(p[1],-30000,30000)
