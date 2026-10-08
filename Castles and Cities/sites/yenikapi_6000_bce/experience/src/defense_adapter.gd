extends RefCounted
## Deliberate boundary: sample the existing rendered/walkable surface once, then
## hand plain integer navigation data to the scene-free independent simulation.
const Nav=preload("res://src/core/defense_navigation.gd")
static func capture(world,defense) -> Dictionary:
	var bounds: Array=defense.content.bounds
	var nav: Dictionary={"origin":bounds.slice(0,2),"width":int(bounds[2]),"height":int(bounds[3]),"cell":int(defense.tuning.cell_cm),"rows":[],"places":{},"signature":""}
	var radius: float=float(defense.tuning.radius_cm)/100.0+float(nav.cell)/100.0*sqrt(0.5)
	for y in range(int(nav.height)):
		var row: String=""
		for x in range(int(nav.width)):
			var p: Array=Nav.at(nav,Vector2i(x,y));var at:=Vector3(float(p[0])/100,0,float(p[1])/100)
			var blocked: bool=world.blocked(at,radius)
			# Homes remain civilian space. Entire current footprints are excluded.
			if not blocked:
				for building in world.buildings:
					var local:=Vector2(at.x-building.at[0],at.z-building.at[1]).rotated(deg_to_rad(float(building.yaw)))
					if absf(local.x)<float(building.size[0])*.5+radius and absf(local.y)<float(building.size[1])*.5+radius:blocked=true;break
			row+="#" if blocked else "."
		nav.rows.append(row)
	for place in defense.content.places:nav.places[place.id]=Nav.nearest(nav,[roundi(place.at[0]*100),roundi(place.at[1]*100)])
	nav.signature=JSON.stringify(nav.rows).sha256_text()
	return nav
