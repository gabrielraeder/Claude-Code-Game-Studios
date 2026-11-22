# PROTOTYPE - NOT FOR PRODUCTION
# native-spike STATE (resume notes)
- [x] step 0: scaffold (.gitignore, project.godot)
- [x] step1: out/extension_api.json + .h + interface.json dumped; godot-cpp cloned 7fd5c4bc; venv scons 4.11.1
- [x] step2: stub ext built debug 86s first; release built (see out/build_*_first.txt). next: write real C++ (src/), gd scripts, bench
- [x] step3: src/native_spike_query.{h,cpp} written (full port + static). next: build debug, gd scripts (gd_movers.gd, gd_static.gd, bench.gd, test_load.gd), measure
- [x] step4: gd scripts + run.sh written; debug dll built (inc 7.8s); test_load PASS (Q2); --import segfaulted (investigate). next: compare, release build, benches
- [x] step5: compare done (out/compare_debug.txt): rays identical, sweeps 188/25920 differ (pose slerp 1ulp, 63/1000). next: release rebuild, benches (out/bench_*.txt) one at a time
- [x] step6: release built. running run_all.sh in background -> out/bench_results.txt (ends with DONE). no compiling until done
- [x] step7: benches done (out/bench_results.txt). A stray 'godot --headless --path . --quit' (PID 10572/43288, mine) hangs; kill was denied by classifier, left running. gdextension reset to default. next: write README.md + REPORT.md, hand back
- [x] step8: found Godot imports src/*.obj and scans godot-cpp/ (500MB) -> added .gdignore in src, godot-cpp, .venv; removed 4 src/*.obj.import by name
- [x] step9: README.md written. REPORT.md write was refused by the tool (subagents return findings as text); content delivered in the final message instead. DONE.
