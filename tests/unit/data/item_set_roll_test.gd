extends GdUnitTestSuite
## Example suite (core-rebuild story 001): proves gdUnit4 runs with commands.test.
## Covers ItemSet.roll, a shared src/data class, with a set built here (no frozen .tres is read).

## Fixture: two items; place 1 can only roll item 0, place 2 only item 1.
const ODDS_FIRST: PackedFloat32Array = [1.0, 0.0]
const ODDS_SECOND: PackedFloat32Array = [0.0, 1.0]
## Fixture seed: any fixed value keeps the test deterministic.
const FIXTURE_SEED: int = 42
## Rolls per check: enough that a zero-weight item would show up if it could be picked.
const ROLLS: int = 200


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
