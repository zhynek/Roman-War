extends "marcus_panel.gd"
## Standalone village entry point; shared presentation uses an explicit adapter.
const VillageContext=preload("marcus_village_context.gd")

func configure(owner_app) -> void:
	configure_context(VillageContext.new(owner_app))
