extends RefCounted
## Shared helper every native-test suite calls in before() (ADR-0007 section 7: closes the
## editor-panel gap, where gdUnit4 started from the panel never runs tools/build_native.sh --check).
## A suite under tests/unit/ that names a native class must preload this file and call problem() inside
## before(); the tools/core_greps.sh rule "native suites call the shared hash helper" checks both.
##
## Usage in a suite:
##   const _GUARD = preload("res://tests/unit/native/native_test_guard.gd")
##   func before() -> void:
##       assert_str(_GUARD.problem()).is_empty()

const _BOOT = preload("res://src/core/native_boot_check.gd")


## "" when the extension is loaded and its source hash matches the sources, otherwise the refusal
## message (it names tools/build_native.sh). [param source_hash_override] exists so a test can feed a
## stale hash without touching a source file.
static func problem(source_hash_override: String = "") -> String:
	return _BOOT.check(_BOOT.ANCHOR_CLASS, source_hash_override)
