extends "res://tools/land_preview.gd"
func run() -> void:
	app=load("res://main.tscn").instantiate();root.add_child(app)
	await process_frame
	var p=app.campaign
	for compact in [true,false]:
		p.state=Driver.at_season(p.rules,compact,32)
		app.show_campaign(p.state,p.rules)
		validate_routes("compact" if compact else "outward")
		validate_paths("compact" if compact else "outward")
	p.state=Driver.initial(p.rules);p.state=p.rules.command(p.state,{"kind":"commission","id":"land_provisioning"}).state
	for i in range(3):p.state=p.rules.advance(p.state).state
	app.show_campaign(p.state,p.rules)
	validate_paths("provisioning");validate_routes("provisioning")
	print("LAND GEOMETRY CHECKS: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
