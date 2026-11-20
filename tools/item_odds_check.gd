extends SceneTree
## Story 004 check: prints the odds table and 2,000 seeded rolls per place group.
## Run: godot --headless --path . -s res://tools/item_odds_check.gd

const ROLLS: int = 2000


func _init() -> void:
	var set: ItemSet = load("res://assets/data/items/item_set.tres") as ItemSet
	var names: Array[String] = []
	for d in set.items:
		names.append(d.id)
	print("odds table (weights, rows = place, columns = %s)" % ", ".join(names))
	for p in set.odds.size():
		print("  place %2d: %s" % [p + 1, str(set.odds[p])])
	var groups: Array = [["leaders 1-2", 1, 2], ["middle 5-8", 5, 8], ["back 11-12", 11, 12]]
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for g in groups:
		var counts: Array[int] = []
		counts.resize(set.items.size())
		counts.fill(0)
		for i in ROLLS:
			var place: int = rng.randi_range(int(g[1]), int(g[2]))
			counts[set.roll(place, rng)] += 1
		var parts: Array[String] = []
		for i in counts.size():
			parts.append("%s %.1f%%" % [names[i], 100.0 * counts[i] / ROLLS])
		print("%s (%d rolls): %s" % [g[0], ROLLS, ", ".join(parts)])
	quit()
