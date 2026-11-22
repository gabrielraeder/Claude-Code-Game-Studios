#pragma once
/// The build marker `DOGWORKS_BUILD:<target>:<SH>:<FH>:END` (ADR-0007 section 7).
/// It is defined only in the SCons-generated native/obj/<variant>/build_marker.cpp, so a hash
/// change recompiles that one file and never the rest. `DogworksCore::build_hash()` references it,
/// so the linker keeps it in the DLL where `tools/build_native.sh --check` finds it by regex.

extern const char dogworks_build_marker[];
