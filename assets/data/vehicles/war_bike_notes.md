# War-bike tuning notes (story 006)

All handling differences from `armored_cart.tres` live in `war_bike.tres`; no code special-cases the bike.
Cart value -> bike value, and why:

| field | cart | bike | rule |
|---|---|---|---|
| accel | 14.0 | 18.2 | +30% |
| max_speed | 26.0 | 24.96 | -4% |
| brake | 32.0 | 34.0 | grippier |
| turn_rate | 2.3 | 2.75 | +20% tighter turning |
| full_steer_speed | 6.0 | 5.0 | full steering sooner |
| high_speed_steer_damp | 0.3 | 0.2 | keeps turning at speed |
| drift_yaw_base / range | 1.25 / 0.85 | 1.6 / 0.95 | tighter drift arc (radius = v / yaw rate) |
| drift_grip | 2.2 | 2.9 | slides less, so a tighter arc |
| radius | 1.0 | 0.85 | thinner body (wall contact) |
| bump_half_length / bump_radius | 0.5 / 0.85 | 0.65 / 0.6 | long thin capsule |
| bump_push_mult | 1.5 | 0.7 | LOWER on purpose: a kart is pushed by the OTHER kart's share, so a lighter bike is shoved more by carts and shoves less |
| bump_knockback (wall) | 1.4 | 1.9 | harder wall bounce |
| bump_speed_loss | 0.1 | 0.4 | loses more speed per kart bump |
| bump_restitution | 0.4 | 0.7 | bounces away harder |
| bump_knock_max | 16 | 22 | |
| spin_time | 1.1 | 1.25 | longer spin-out |
| wall_impact_max_speed_loss | 0.6 | 0.7 | |
| hit_slowdown_profiles | 0.3/0.3/0.6 s | 0.4/0.45/0.8 s, lower floors, steeper decel | harsher |
