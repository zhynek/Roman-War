# Village presentation reuse — 2026-10-07

Matched source measurements use the same ordinary public-command recipe, Godot
4.4.1, 1280×800 view and M3 Max. The pre-edit main baseline was `138561d`.
`experience/tools/lifecycle_profile.gd` preserves the exact original temporary
profiling script as a reproducible gate. No competing Godot process ran during
these measurements. Callback times below exclude the subsequent rendered frames.

| Operation | Baseline ms | Revised ms |
|---|---:|---:|
| Open lifecycle | 28.717 | 28.269 |
| Reopen unchanged panel | 12.453 | 0.109 |
| Commission assembly shelter | 2006.877 | 510.081 |
| Ordinary seasonal refresh | 1131.414 | 895.027 |
| Civic completion | 1128.443 | 1216.819 |
| Unchanged scene refresh | 14.943 | 15.482 |

The commissioning journey search component was 1803.737 ms before and 315.657 ms
after. Reuse considers only an existing searched outdoor route from the exact
same origin, with an endpoint within four metres of the new target and a
collision-clear connector. It does not chain previously appended connectors.
Existing geometry invalidation checks each route; invalidated paths are never
reused. Navigation, positions and animation remain presentation only.

The UI retains controls when its state, message, view size, selection, page,
preview and planning-room signature are unchanged. Commands/season changes still
refresh; synchronous command and seasonal input guards remain authoritative.

Retained route walking, cold-build geometry, public command, save and interface
checks pass with the town source gates. Final source/exact-app rendered and
interaction gates are required by the local builder. There is no claim of a
civic-completion improvement: that sample is slightly slower, and some later town
refreshes still pause for around 1–1.5 seconds. Frame sampling and GPU readiness add
time beyond callbacks. Neither these local samples nor the separate parent CI
investigation establishes performance on Intel Macs or shared Ubuntu runners.

Logs: `build/yenikapi-0.12-baseline/lifecycle-profile.log` and
`lifecycle-profile-after.log`; final build verification retains the same source
and exact-app profiles.
