class_name ArtNoise
extends RefCounted
## The map's hash, lifted out of MapGeometry so the landmass and the building
## art wobble by one rule. Never randf(): a given building must look identical
## every frame, every session and in every screenshot, which is the same
## replay-determinism promise CLAUDE.md makes about the campaign itself.


static func hash01(key: String, salt: int) -> float:
	var h: int = 2166136261 ^ ((salt * 2654435761) & 0xffffffff)
	for i in key.length():
		h = ((h ^ key.unicode_at(i)) * 16777619) & 0xffffffff
	return float(h) / 4294967296.0


static func noise(key: String, t: float) -> float:
	var cell := int(floor(t))
	var f := t - float(cell)
	var a := hash01(key, cell & 0xffff) * 2.0 - 1.0
	var b := hash01(key, (cell + 1) & 0xffff) * 2.0 - 1.0
	return a + (b - a) * f * f * (3.0 - 2.0 * f)


static func swing(key: String, salt: int, amount: float) -> float:
	## A signed wobble in [-amount, +amount] — the shape most glyphs want.
	return (hash01(key, salt) - 0.5) * 2.0 * amount
