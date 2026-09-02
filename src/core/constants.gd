class_name Constants
## Shared enums-as-strings and ordering helpers. Content never lives here —
## only structural vocabulary shared between schemas and engine.

const SETTLEMENT_LEVELS: Array[String] = [
	"village", "town", "large_town", "minor_city", "large_city", "huge_city"
]

const TAX_LEVELS: Array[String] = ["very_low", "low", "normal", "high", "very_high"]

const SEASONS: Array[String] = ["summer", "winter"]

const CULTURES: Array[String] = [
	"roman", "greek", "eastern", "carthaginian", "egyptian", "barbarian", "neutral"
]

const BUILDING_KINDS: Array[String] = [
	"government", "walls", "barracks", "stables", "archery_range", "siege_workshop",
	"naval", "market", "farms", "roads", "port", "mines", "health", "entertainment",
	"execution", "education", "temple"
]

const STANCES: Array[String] = ["war", "neutral", "trade", "alliance", "protectorate"]

## Unit-class roles (data/unit_classes.json) that must all be present in a force
## for the combined-arms bonus: a line to hold, a shock arm to break, missiles to wear.
const COMBINED_ARMS_ROLES: Array[String] = ["line", "shock", "missile"]


static func level_index(level: String) -> int:
	return SETTLEMENT_LEVELS.find(level)


static func level_at_most(level: String, cap: String) -> bool:
	return level_index(level) <= level_index(cap)
