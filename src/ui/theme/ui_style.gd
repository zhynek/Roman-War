class_name UiStyle
## The single source of UI color, typography and cosmetic hashing. Every
## visual constant lives here, not scattered through panels — and all
## cosmetic randomness (terrain glyph jitter, tribal wall wobble) derives
## from stable ids through fnv(), never from the campaign RNG, so redrawing
## the map can never steer a game outcome.

## --- the map ---------------------------------------------------------------

const SEA_DEEP := Color(0.075, 0.165, 0.235)
const SEA_SHALLOW := Color(0.125, 0.255, 0.335)
const SEA_SHELF := Color(0.42, 0.62, 0.70, 0.30)  ## coastal shallows halo
const LAND_BASE := Color(0.804, 0.755, 0.639)     ## parchment under everything
const COAST_LINE := Color(0.246, 0.207, 0.155)
const PROVINCE_BORDER := Color(0.22, 0.18, 0.12, 0.30)
const FOG_VEIL := Color(0.055, 0.075, 0.105, 0.62)
const ROAD := Color(0.42, 0.325, 0.22)
const ROAD_PAVED_CORE := Color(0.87, 0.81, 0.68)
const SELECTION := Color(0.98, 0.95, 0.85)
const RANGE_TINT := Color(1.0, 0.93, 0.45, 0.20)
const RANGE_EDGE := Color(1.0, 0.93, 0.45, 0.75)
const SIEGE_RED := Color(0.86, 0.26, 0.16)
const CAPITAL_GOLD := Color(1.0, 0.87, 0.42)
const LABEL_INK := Color(0.965, 0.945, 0.895)
const LABEL_OUTLINE := Color(0.06, 0.07, 0.09, 0.85)
const SEA_LABEL := Color(0.72, 0.83, 0.90, 0.75)

const TERRAIN_FILL := {
	"plains": Color(0.727, 0.769, 0.575),
	"forest": Color(0.492, 0.606, 0.416),
	"hills": Color(0.780, 0.700, 0.512),
	"mountains": Color(0.700, 0.649, 0.580),
	"desert": Color(0.878, 0.808, 0.596),
	"steppe": Color(0.812, 0.769, 0.545),
	"marsh": Color(0.573, 0.671, 0.588),
}
const TERRAIN_GLYPH := {
	"plains": Color(0.55, 0.60, 0.40, 0.55),
	"forest": Color(0.27, 0.40, 0.24, 0.85),
	"hills": Color(0.55, 0.47, 0.31, 0.75),
	"mountains": Color(0.38, 0.34, 0.29, 0.9),
	"desert": Color(0.68, 0.60, 0.40, 0.6),
	"steppe": Color(0.60, 0.55, 0.35, 0.55),
	"marsh": Color(0.33, 0.44, 0.37, 0.8),
}

## --- shared chrome ---------------------------------------------------------

const PARCHMENT := Color(0.95, 0.9, 0.75)  ## the accent the panels share


## --- cosmetic hashing ------------------------------------------------------

static func fnv(text: String, salt: int = 0) -> int:
	## 32-bit FNV-1a over a stable id — the one sanctioned source of UI
	## randomness. Engine-version-proof, unlike String.hash().
	var h := 2166136261
	for i in range(text.length()):
		h = ((h ^ text.unicode_at(i)) * 16777619) & 0xFFFFFFFF
	h = ((h ^ (salt & 0xFF)) * 16777619) & 0xFFFFFFFF
	h = ((h ^ ((salt >> 8) & 0xFF)) * 16777619) & 0xFFFFFFFF
	return h


static func jitter(text: String, salt: int = 0) -> float:
	## Deterministic [0, 1) from a stable id.
	return float(fnv(text, salt)) / 4294967296.0
