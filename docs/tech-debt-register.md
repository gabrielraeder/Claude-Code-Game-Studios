## Technical Debt Register

Last updated: 2026-11-19
Total items: 3 | Estimated total effort: S + S + S

| ID | Category | Description | Files | Effort | Impact | Priority | Status | Added | Sprint |
|----|----------|-------------|-------|--------|--------|----------|--------|-------|--------|
| TD-001 | Code Quality | The placeholder cart's block sizes (body, nose, wing, driver) are literals in code, not data — from production/epics/dogworks-racing-kennel-kingdom/story-001-driving-and-drift.md | src/vehicle/kart_visual.gd | S | Low | — | Open | 2026-11-19 | Backlog |
| TD-002 | Code Quality | IPv6 host addresses are not parsed in join (the port split expects one colon); IPv4 and Tailscale 100.x work — from production/epics/dogworks-racing-kennel-kingdom/story-002-online-multiplayer.md | src/net/net_session.gd | S | Low | — | Open | 2026-11-19 | Backlog |
| TD-003 | Code Quality | Debug options and drivers (--ram, --park, --port, --autopilot) and the stress/bump scripts live inside src/debug/ and tools/; the game never depends on them but they ship in the same folders — from production/epics/dogworks-racing-kennel-kingdom/story-002-online-multiplayer.md | src/debug/, tools/ | S | Low | — | Open | 2026-11-19 | Backlog |
