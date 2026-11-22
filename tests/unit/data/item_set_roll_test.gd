extends GdUnitTestSuite
## Example suite (core-rebuild story 001): proves gdUnit4 runs with commands.test.
## Covers ItemSet.roll, a shared src/data class, with a set built here (no frozen .tres is read):
## zero weights, a place past the last row, and a weighted row with a pinned seeded sequence.

## Fixture: two items; place 1 can only roll item 0, place 2 only item 1.
const ODDS_FIRST: PackedFloat32Array = [1.0, 0.0]
const ODDS_SECOND: PackedFloat32Array = [0.0, 1.0]
## Fixture seed: any fixed value keeps the test deterministic.
const FIXTURE_SEED: int = 42
## Rolls per check: enough that a zero-weight item would show up if it could be picked.
const ROLLS: int = 200
## Fixture: one row of unequal weights (item 1 twice as likely as items 0 and 2).
const ODDS_WEIGHTED: PackedFloat32Array = [1.0, 2.0, 1.0]
## The exact picks ItemSet.roll returns for ODDS_WEIGHTED with seed FIXTURE_SEED (Godot's PCG32
## RandomNumberGenerator, recorded on 4.8-beta3). A seeded RNG is deterministic, so any change
## means roll() or its use of the RNG changed.
const WEIGHTED_SEQUENCE: Array[int] = [0, 1, 1, 0, 2, 0, 2, 0, 0, 2, 0, 0]


func _make_set() -> ItemSet:
	var set := ItemSet.new()
	set.odds = [ODDS_FIRST, ODDS_SECOND]
	return set


func test_roll_zero_weight_item_is_never_picked() -> void:
	# Arrange
	var set: ItemSet = _make_set()
	var rng := RandomNumberGenerator.new()
	rng.seed = FIXTURE_SEED
	# Act / Assert
	for i in ROLLS:
		assert_int(set.roll(1, rng)).is_equal(0)
		assert_int(set.roll(2, rng)).is_equal(1)


func test_roll_place_past_last_row_uses_last_row() -> void:
	# Arrange
	var set: ItemSet = _make_set()
	var rng := RandomNumberGenerator.new()
	rng.seed = FIXTURE_SEED
	# Act
	var picked: int = set.roll(set.odds.size() + 5, rng)
	# Assert
	assert_int(picked).is_equal(1)


func test_roll_weighted_row_seeded_sequence_is_exact() -> void:
	# Arrange
	var set := ItemSet.new()
	set.odds = [ODDS_WEIGHTED]
	var rng := RandomNumberGenerator.new()
	rng.seed = FIXTURE_SEED
	# Act
	var picks: Array[int] = []
	for i in WEIGHTED_SEQUENCE.size():
		picks.append(set.roll(1, rng))
	# Assert
	assert_array(picks).is_equal(WEIGHTED_SEQUENCE)
