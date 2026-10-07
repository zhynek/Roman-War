# Retained compatibility fixture

`lifecycle-0.11-paid.json` is the unchanged public-command QA save
`paused-lifecycle_assembly.json` from the verified 0.11.0 local build, frozen payload
`227eca38b2919d7d0abea1820b5823958a2460ba`. It is generated test data, not a player's save.
It contains a partially worked, paused assembly shelter with its original paid
contract. Do not rewrite it when authoring a new lifecycle profile.

SHA-256: `b0e0af7a47ffe5febe15d189bce0d4ffcb988180112dbf0412da293d607ae872`.

`town_checks.gd` loads it through the real reader, explicitly adopts town,
compares all prior state fields and rechecks the original bytes. New town entry,
stress and recovery saves are generated outside the source tree with replayable
public-command recipes; they are not stored here as hand-authored stage grants.
