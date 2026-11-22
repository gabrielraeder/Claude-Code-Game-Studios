# gdUnit4 mock() and spy() on a native class (story 066, ADR-0007 Verification Required 1)

Observed with gdUnit4 6.2.3, Godot 4.8-beta3, on `ToolchainProbe` (a RefCounted native class). Tests:
`tests/unit/native/native_toolchain_test.gd`, `test_mock_of_native_class_does_not_intercept_bound_native_methods`
and `test_spy_of_a_built_native_object_does_not_forward_to_the_original_instance`.

- `mock(ToolchainProbe)` returns an object (not null), but calling a bound native method on it runs the
  native method (the unbuilt `!built` guard fired), not a mock stub. `verify()` saw no interaction
  (first exploratory run: "Expecting interaction on:"). So mock() does not stand in for a native class.
- `spy(built_probe)` returns an object, but `echo_int(9)` on it did not return 9 (it returned 0): it is a
  copy, not the built original. A spy does not wrap a native instance.
- Consequence, as the ADR expected: tests drive the real class. gdUnit4 itself drives native classes fine
  (24 test cases in the suite, see logs/gdunit-native-7.log).
- gdUnit4 reports native `ERR_FAIL_*` errors as push errors: use `assert_error(...).is_push_error(text)`.
  The text it matches is the macro text (`Condition "!built" is true. Returning: 0`,
  `Method/function failed. Returning: Ref<ToolchainProbe>()`), not the custom `_MSG` message.
