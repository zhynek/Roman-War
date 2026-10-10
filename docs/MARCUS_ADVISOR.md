# Marcus: a counselor across generations

Development plan recorded in Isengard on October 8, 2026, before implementation:
**Marcus advisor — guided tutorial and private ElevenLabs voice**, assignment
`43bbb7f8-11f2-4b5c-9d62-cef289a01aae`, Roman-War project. Work starts from
`origin/main` at `869dca1` on `codex/marcus-advisor`.

## The experience

Marcus is an original fictional counselor inspired by the reflective bearing of
Marcus Aurelius. He stands outside the game's chronology: leaders die, cities
change, and his relationship with the player continues. His role is to help the
player understand a decision, its cost, and the people affected by it. He is calm,
specific, occasionally challenging, and never an infallible oracle.

The opening premise is **The Measure of a Ruler**. Divine voices ask the player
to build something that can survive its founder. They disagree about what makes
it worthy. Marcus begins with the immediate human obligations: food, shelter,
work, and safety. This is deliberately invented mythology, not an archaeological
claim about Yenikapı or a claim that a Roman emperor lived in 6000 BCE.

The first implementation targets the independent **Yenikapı — Early Settlement**
project. Its recent playable development and eleven existing lessons provide
the initial teaching material. The parent Roman campaign is a separate
application connected by the campaign adapter described below.

## Milestones and acceptance

1. **Marcus and the opening tutorial.** A persistent bottom-right portrait opens
   a readable guide and conversation panel. The introduction can be skipped and
   replayed. Lessons use the existing authored help and open the real controls
   through an explicit “Show me” action. Returning to Marcus preserves the lesson.
   Authored help remains usable offline.
2. **Contextual text and ElevenLabs voice.** A private ElevenLabs Agent supplies
   the LLM and speech in one conversation. Typed questions and current visible
   game information produce streamed response text and matching spoken output.
   Provide connection state, mute, stop, and bounded failure behavior. Voice
   starts only after the player connects. Microphone input is a later increment.
3. **Secure live setup and acceptance.** The provider key stays in the local
   session service. Check private-agent authentication before issuing a signed
   connection. Configure voice, prompt, knowledge, PCM format and events. Then
   verify a real question with matching audio/text and interruption. Document
   anything not verified rather than equating a configured client with a live
   provider integration.
4. **Roman campaign adapter.** Keep Marcus present between map and city views;
   supply only the campaign facade's visible reports and selection. Teach its
   existing order preview, settlement panels and seasonal turn flow.
5. **The council.** Unlock an original elderly senator/philosopher for governance
   and a military advisor through actual game prerequisites. Their expertise,
   loyalties and disagreements become narrative context. Greek philosophical
   inspiration and a Roman senatorial appearance are creative influences, not
   a claim that the institutions are historically interchangeable.
6. **Divine mandates and seasonal councils.** Design worship, temples and
   competing mandates as explicit data-driven rules with visible tradeoffs.
   A seasonal council presents counsel after the deterministic season resolves.
   Neither spoken dialogue nor an LLM decides rewards, outcomes or unlocks.

The campaign integration, reactive tutorial, Lucius and Gaius specialists,
authored and generated seasonal councils, Zeus/Ares patronage and dilemmas,
source-backed campaign memory and the successor's first council are implemented.
The latest records below supersede older “next phase” notes, which remain as
development history. A larger pantheon and multi-season divine story arcs remain
future work.

## Boundaries

- LLM advice is presentation only. It cannot dispatch commands, purchase,
  adopt a rules profile, advance seasons, mutate saves, consume campaign RNG,
  or call the battle resolver. “Show me” navigates; the player acts. The divine
  patronage page exposes explicit confirmed player commands through the Game
  facade; no model response can pledge or renounce on the player's behalf.
- Tutorial position and mute preference belong in a separate `user://` config.
  Conversation text stays in memory and is not written into campaign saves.
- Current context is constructed from an allowlist when the player asks. Never
  send the full game state, a complete forecast, or a quote's candidate state.
  Hidden incident timing and undiscovered enemy information remain private.
- All authored game prose lives in `data/marcus.json` and the existing
  `data/visual_commands.json`; each new content table has a schema and validator.
- Portrait art is procedural and original. No raster assets or cloned actor
  voices are added. Voice character is an older, measured, warm male speaker.
- Provider credentials never belong in GDScript, `.pck` exports, saved games,
  source control, example URLs, logs, or Isengard reports. GitHub Actions secrets
  are not a game-runtime key service and their values cannot be fetched back.
- The initial service is loopback-only for development. A shipped multiplayer
  or public client needs authenticated player sessions, per-player quotas,
  abuse controls and a protected hosted broker before remote access is enabled.

## Implementation and configuration

The retained advisor is a sibling of the village's existing HUD panels; their
refresh cycles cannot destroy a conversation. `marcus_voice.gd` obtains a signed
WebSocket connection through `tools/marcus_broker.py`. ElevenLabs handles the LLM
and speech; a separate OpenAI or Anthropic key is not needed for that route.

The server-side persona is in [`marcus/agent-prompt.txt`](marcus/agent-prompt.txt).
Configuration and the exact local launch command are recorded in
[`marcus/SETUP.md`](marcus/SETUP.md). A future custom LLM can replace the provider's
built-in model without distributing its key in the game.

Official protocol references:
[ElevenLabs WebSockets](https://elevenlabs.io/docs/eleven-agents/libraries/web-sockets),
[ElevenLabs authentication](https://elevenlabs.io/docs/eleven-agents/customization/authentication),
and [OpenAI API authentication](https://developers.openai.com/api/reference/overview).

## Verification policy

Follow the weekly review policy: no broad game suite and no new tutorial tests
during this development cycle. Inspect the changed implementation before one
direct Godot import/render pass and validate only the new content. Focused
credential-boundary tests are allowed by the policy's security exception.
No CI polling or release publication is part of this slice. Isengard acceptance
remains a human decision.

## Development checkpoint — October 8, 2026

Milestones 1 and 2 are implemented in source. The new content validator reported
`MARCUS DATA: 0 errors`; Godot 4.4.1 imported the scripts without errors. Direct
rendering found initial container sizing problems, which were corrected and
visually rechecked: the introduction scrolls inside its panel, connection controls
remain visible, the portrait launcher fits, and the chat composer is readable.
The final runtime log contains no script errors. No game suite was run.

The broker's fourteen focused credential checks passed under the security
exception. The private ElevenLabs agent is published, and one dashboard text
question received a relevant reply that correctly acknowledged missing village
state. The preview conversation was ended. This does **not** verify native
streamed audio, text/audio alignment or interruption: those milestone-3 checks
are pending private credential entry through the launcher.

An Isengard progress report was submitted for human review, report
`761b236c-5753-4a39-99c7-5faee6dbe576`. The assignment remains In progress;
no report was accepted and no game release was built. Work remains local on
`codex/marcus-advisor`.

## Implementation follow-up

The initial tutorial and native conversation implementation is complete in
source. A follow-up review corrected turn completion: streamed text no longer
unlocks the question composer before the provider finishes the answer, muting
does not bypass the pending reply, and a late completion from an older response
cannot finish the current one. Fixed broker error codes now distinguish missing
credentials, private-agent configuration, rate limits and a busy service without
exposing provider response bodies. The village README links the entry point and
private setup. Connection-status prose is included in content validation.

Direct verification ran the changed transport with sample start/delta/stop and
completion events in Godot: `answering=true` through the stream, `false` at
completion, still `true` after an older completion, and `false`/`muted` after the
current completion. Content validation again reported zero errors. This direct
function check made no network request and is not a live provider acceptance.
The prior import, rendered UI inspection and fourteen broker security checks
remain applicable; the broad game suites were not repeated.

**Remaining acceptance:** supply the dedicated ElevenLabs key privately, launch
the configured game, and verify one actual contextual question with matching
text and audible speech, then mute and disconnect. Until that succeeds, milestone
3 and the Isengard assignment remain In progress. No public deployment or
distribution with shared credentials is part of this development phase.

## Campaign phase: Marcus across the Roman campaign

The user authorized this phase on October 8, 2026. Its plan was appended to
the existing Isengard assignment before editing. Work proceeded on offline
campaign integration while private native voice acceptance remained pending:

1. Extract the retained advisor presentation from its village-specific context
   builder so both applications use the same connection and transcript behavior.
2. Add an adapter for the campaign facade's visible selection, city factor
   breakdowns, known forces, order previews and resolved seasonal reports. Keep
   hidden rosters, undiscovered regions and full saves out of provider context.
3. Author a campaign opening and replayable lessons for city management, public
   order, movement previews and advancing a season; navigation remains explicit.
4. Offer an optional **Review the season with Marcus** after the existing turn
   presentation completes. Summarize actual outcomes and tradeoffs without
   advancing turns or issuing orders.

Acceptance: Marcus remains available across map/city transitions, answers a
question using current visible facts, explains a resolved season, and preserves
the campaign state and RNG while advising. This establishes the integration
needed for later governance/military specialists and divine councils. Specialist
unlocks, new gods/temple rules and multi-advisor conversations belong to the
following phase; they are not part of this proposed adapter implementation.

## Campaign implementation

`CampaignSession` owns one retained Marcus panel above the map and Roma views.
The shared presentation, portrait and ElevenLabs transport remain under the
standalone village project so that its exports remain self-contained. The parent
loads those same scripts explicitly; each game supplies its own context adapter,
content and separate preference file. Conversation history stays in memory and
is cleared when a campaign save is loaded.

The campaign content table and schema author a new opening, six lessons and the
optional seasonal review. Navigation only inspects the capital, opens an existing
drawer, Controls or Dispatch, or opens the ledger when already in Roma. It never
enters Roma automatically, because initial city entry establishes campaign state.

The context adapter uses known settlement surveys, own settlement factor reports,
observed enemy presence, own force summaries and order previews. It never sends
full saves, hidden rosters, unknown regions, raw journals or campaign RNG. During
live city battles it reads only the detached snapshot already used by the UI.
The presentation blocks underlying camera/command input while open; it does not
pause or alter the battle worker.

A seasonal offer appears after turn playback and Dispatch are finished, or after
city season advancement finishes. A pending city battle defers the briefing until
that view closes. Reopening the same Dispatch does not repeatedly offer it. The
latest filtered headlines are readable offline; voice still requires explicit
connection. A new season clears the old offer. No advisor unlock, temple rule,
divine reward, new simulation system or save migration was introduced.

The private agent prompt was updated and published to distinguish the two games,
recognize existing campaign temples, respect stale surveys, and explain partial
season/battle context. Provider credentials remain exclusively in the broker.

Campaign verification: data/schema validators returned zero errors; both Godot
projects imported cleanly. The campaign opening, map lesson, seasonal review and
shared village panel were rendered and inspected. Direct output confirmed
unchanged full campaign state (including RNG) for advisor context, lesson
navigation, briefing and map/city round trip; conversation count remained 1
across views and reset to 0/disconnected on load. The seasonal offer stayed
hidden during playback and Dispatch and appeared after dismissal. The sampled
briefing contained 16 visible reports in 4,832 context bytes. Fresh-campaign
season availability and focus confinement were corrected during inspection.
Runtime logs contained no script errors. Live provider audio remains unverified.

Verified by: data/schema validation, Godot imports, rendered advisor walkthrough and direct state/retention checks. Tests: not run (weekly review policy).

Proposed governance phase (implemented below): one governance specialist unlocked by an existing,
explicit building prerequisite, with a visible explanation of the unlock and
counsel based on reported city factors. Keep the unlock deterministic and its
counsel advisory; defer a full council and divine mandates until that smaller
loop is working. Native live text/audio acceptance remains a separate immediate
integration dependency, not a reason to claim provider behavior already works.


## Governance specialist implemented — October 8, 2026

The executable [next-phase prompt](advisors/NEXT_PHASE_PROMPT.txt) was recorded in
the existing Isengard assignment before development. Lucius now has an original
procedural portrait, four authored lessons, a selected-city reading, and a
separate published private ElevenLabs persona with Declan Sage's voice.

`data/advisors.json` supplies the existing government-chain prerequisite:
completed tier three or above in an owned settlement. `AdvisorRules` awards once
at creation/season close without RNG. `advisor_unlocks` records the original
turn and region; save validation is additive and only saves missing the field
receive legacy backfill. UI status calls never grant unlocks. Losses do not
remove an earned advisor. The campaign shows locked progress and switches
explicitly between retained panels; switching stops the prior connection,
loading clears both conversations and restores Marcus.

Lucius's offline reading contains bounded player-visible factor lists and
reported societal values for a selected owned settlement. Survey age, missing
values and truncated lists are labeled. During a city battle, economic reads
are deferred and only the already-presented detached snapshot is available.
The broker accepts a strict `marcus`/`lucius` selector mapped to server-held IDs;
it rejects arbitrary IDs/URLs, duplicates and missing specialist configuration.
Each agent must remain private on every session mint. Provider keys never enter
the game process, content, saves or logs.

Evidence: both data validators and Godot imports succeeded. Sixteen focused
credential checks and three focused migration checks passed under the testing
policy exceptions. A rendered isolated campaign showed locked tier two with
one queued project; the season completed tier three and awarded Lucius in turn
one. Actual switch-button callbacks preserved one distinct transcript entry per
advisor, a city reading left full campaign state unchanged, and loading a
locked save reset both to zero/Marcus. The reading contained four sections and
6,257 context characters, with army context absent. Locked, welcome, reading,
Roma and village panels were inspected. First-open autowrap overflow was fixed;
at 1280×800 the locked panel settled at (804,16), size 460×678, with scrolling
content and connection controls visible. Runtime logs had no script errors.

Live native audio/text acceptance remains pending the private API key. No
public deployment, broad suite or release push was performed.

Verified by: data validation, Godot imports and rendered walkthrough. Tests: not run (weekly review policy), except 16 credential checks and 3 migration checks, which passed.

Next logical phase: a small season council with Marcus and Lucius presenting
separate, bounded viewpoints on the latest Dispatch and the selected city's
reported conditions. Keep it optional and player-controlled, and finish live
native voice acceptance before expanding to another specialist or divine rules.


## Three advisor phases implemented — October 9, 2026

This session began from clean `245503c` on `codex/marcus-advisor`, retaining the
integrated waterways. The complete plan was recorded before implementation in
Isengard assignment `78dc60e5-c926-4d29-9645-476374d22528`, linked to the original
`762ed14c-6d92-44ef-b99f-675b4b2be04c`. The dedicated reporting agent maintains
[the progress record](advisors/NEXT_THREE_PHASES_PROGRESS.txt). No push or release
was authorized.

### Reactive Marcus

`data/reactive_tutorial.json` and its schema author five encounters. The
scene-free `AdvisorTutorialRules` records real season resolution, completed
construction, mustered units/actual marches, a new negative-treasury or sub-80
public-order crossing, and declarations of war/involved battles. Queuing a
project or reading a report is insufficient. The invitation only polls saved
evidence; it never records progress or consumes RNG from a frame callback.

The additive `advisor_tutorial` ledger travels with the campaign save. It stores
the baseline, last inspected season, previous strain state and first evidence,
status and postponement for each encounter. Saves missing it establish a current
baseline: historical seasons and continuing old strain do not generate a flood.
A loaded save is the campaign identity; loading an earlier save restores that
save's earlier progress. Separate campaigns/save forks have independent ledgers.
No machine-global completed flag suppresses another campaign's lessons.

Invitations wait for battles, pending defense, presentation and Dispatch. Show me
uses existing inspection controls, preferring the milestone's still-owned city.
Acknowledgment/dismissal is permanent in that save; postponement lasts until the
next resolved season. The archive remains replayable and Ask prepares a question
without connecting. The separate rewarded Guided mode is unchanged.

### Gaius

`data/gaius.json`, the shared advisor schema and `gaius_portrait.gd` define an
original commander with five lessons and a procedural portrait. The existing
`AdvisorRules` awards his permanent seat for an owned completed tier-three
barracks. All culture-specific barracks use their existing chain. Existing saves
with unlock records award a newly introduced advisor at an eligible season close;
status reads cannot award him. Session availability is seeded before a resumed
battle worker starts and cached throughout battle presentation.

The advisor registry retains separate panels, contexts, preferences and
conversations. Switching closes the previous voice before opening another.
Gaius's military adapter uses only owned force summaries, known destination
terrain and the actual final route approach, order previews, and observed hostile
presence. Neutral/allied forces are not labelled enemies. Enemy rosters, precise
strength and estimator results are absent. Tactical advice takes the detached
panel snapshot, selected defending formations and revealed attacker presence;
it never calls the running worker's campaign/economy readers.

The broker adds only the allowlisted `gaius` selector and
`ELEVENLABS_GAIUS_AGENT_ID`. Missing/duplicate configuration fails explicitly.
A distinct private Adam voice persona is configured in the existing owner-only
credential file. Provider credentials remain in Python; the child environment,
prompts, saves and repository never receive the key.

### Living council and dilemmas

`living_council.gd` is a presentation controller over the existing transport.
**Hear the council** requires an owned selected city and the current resolved
season's visible reports. It freezes a bounded deep copy, filters locked seats
and their interpretations, and includes only currently eligible authored divine
alternatives and their quoted effects. Quote signatures never leave the game.
Marcus chairs; Lucius weighs institutions; Gaius weighs defense and recurring
costs. Each gets one explicit question after a muted introduction. Every preceding
connection closes before the next opens.

Data sets limits of three turns, 60 requested words/720 characters per answer,
45 seconds per speaker, 140 seconds overall, and 18,000 snapshot bytes. The
transport's separate 24,576-byte ceiling includes prior turns. No retries or
background debates occur. Mute preserves text; stop, close, tab/speaker/view or
selection changes, new seasons, load and exit cancel playback. The written
perspectives remain available when the provider is absent or fails.

`data/divine_dilemmas.json` authors Zeus's city petition and Ares's levy/fields
choice. `DivineDilemmaRules` offers existing low-tax settings, Public Works,
Legion Levy or refusal. It requires ownership, the current patron's completed
matching temple, at least one season after the pledge and a two-season global
cooldown. Each dilemma resolves once per campaign. Review quotes show exact
existing tax factors or population-based upkeep, full-strength edict effects,
settling delay and revocation cooldown. Confirmation rechecks a canonical hash
of the relevant owned state and rules before applying the existing policy and
writing an additive receipt. Repeated clicks, patron changes and loads cannot
reapply a recorded outcome. Refusal has no hidden penalty; Legion Levy creates
no units. Generated dialogue has no command path.

### Observed verification and limits

The isolated native walkthrough queued legal construction/recruitment, resolved
the military prerequisite, observed invitations, followed read-only navigation,
declared war, pledged Zeus and requested the council. All three speakers streamed
text and played native PCM sequentially. The shared snapshot was 7,530 bytes;
three replies were 294/377/404 characters. No playback overlap or campaign/RNG
mutation occurred. The discussion contrasted civic legitimacy with recurring
public-service and garrison costs. Mute stopped audio; changing selection stopped
and disconnected a second explicitly requested discussion.

Public Works was quoted at 260.208 per season for population 10,008, with five
settling seasons, four revocation-cooldown seasons, and civic +7/growth +0.5/
burden +2 at full strength. Cancel changed nothing. Confirm set the existing
edict and one turn-3 receipt without an upfront charge or RNG draw; a repeated
confirmation did nothing. Load retained the edict, receipt, Gaius and dismissal,
while clearing all transient conversations/council playback.

A prepared 20-unit garrison with one denarius and an actual low-tax season
produced treasury -1,725 through normal income/upkeep and recorded strain. A
separate high-tax/mustering attempt did not cross the threshold, and was not
counted as success. The active practice battle supplied detached tactical
context without faction finances and blocked live council generation. Offline
council failure preserved all authored seats. Final caption/quote screens and the
standalone village's 11-lesson Marcus panel were inspected in isolated storage.

The provider omitted `agent_response_complete` even when configured. The shared
read-only transport now uses accepted final `agent_response`, queued PCM and a
500 ms settling interval; stale and muted-audio safeguards remain. One focused
escaped-bug regression passed; its synthetic headless teardown still reports an
ObjectDB warning. The real campaign and village walkthroughs exited cleanly.
Technical playback was verified; subjective voice character and pacing still
need the player's listening review. This remains a private local development
service, with no multiplayer entitlement or hosted production deployment.

Verified by: data/schema validation, Godot import, isolated native campaign and village walkthroughs, and focused exception checks. Tests: broad suites not run (weekly review policy); 21 credential, four tutorial-save, five dilemma money/save checks and one transport regression passed.

## Persistent campaign memory — October 10, 2026

This phase begins at clean `079353e` and reuses authoritative saved history.
The full plan and acceptance criteria were recorded before implementation in
Isengard assignment `3b8ae6d4-8945-41ef-a85a-9e5c8354b542`, linked to the earlier
advisor assignments. The dedicated reporter maintains
[the plan](advisors/MEMORY_PHASE_PLAN.txt) and
[observed progress](advisors/MEMORY_PHASE_PROGRESS.txt).

`AdvisorMemoryRules.project` and `Game.advisor_memory` are deterministic,
scene-free, read-only projections. They write neither history nor RNG, add no
save fields and keep no machine-global archive. Existing chronicle, character,
reign, divine-choice and patron-honor records provide persistence. Missing old
fields yield unknown/empty history; loading an earlier campaign save restores
that save's earlier facts. Generated conversation is never promoted to evidence.

`data/advisor_memory.json` supplies safe templates, UI text and advisor priority
lists, validated by its schema and cross-reference checks. `balance.advisor_memory`
sets 12 page records, six provider-context records, two earlier reign summaries,
4,096/16,000-byte compact/page caps, 96-character names and 768-character summaries.
Selection prefers a validated requested source, then the selected currently owned
city, then the advisor's authored priorities, recency and stable source reference.
The complete result is trimmed to its byte budget with accurate omission counts;
focus is reported only if its record survives in the returned selection.

The global annals are not a visibility boundary. This projection first requires
player faction involvement, then resolves allowlisted subjects and numeric
fields. Foreign-only records, hidden troop counts, capture loot/population and
unknown or malformed entries do not pass. It never exports the raw chronicle or
full character dictionaries. The current leader comes from actual living player
characters; the reign start is supplied only when the saved reign ledger names
that same leader. Earlier reign totals are explicitly the character's recorded
lifetime deeds at closure. Divine receipts carry a choice, city and turn, without
inventing a ruler attribution, motive, past quote or continuing policy. Former
pledges and renunciations cannot be reconstructed from the current patron ledger.

Every unlocked campaign advisor has a guarded **Campaign memory** page with
source labels, dates, role perspective, ruler continuity, omission notices,
refresh, return to lessons and read-only Annals navigation. Asking about a record
revalidates it and only prefills the conversation. Clear focus restores normal
selection. Connection/send rechecks focused sources; load clears source selection,
question text and transient conversations. Marcus, Lucius and Gaius inherit the
same boundary but use different role priorities. The standalone village gains no
campaign memory dependency or navigation.

Ordinary conversations add one compact `campaign_memory` snapshot. A living
council adds one shared chair-selected snapshot frozen with its existing visible
season evidence, rather than three duplicated histories. All model instructions
separate recorded facts, present conditions and interpretation. No background
request or automatic spending was added. Memory reads return before campaign
history traversal while the tactical view owns a battle worker; tactical
conversations receive only their existing detached snapshot.

Observed locally: an isolated campaign used a prepared old-age prerequisite,
then actual yearly processing changed Appius Claudius to Manius Valerius. The
saved prior reign and new current ruler appeared correctly. An actual legal Zeus
pledge and confirmed Public Works choice supplied the divine receipt. Role
snapshots were 1,946–1,947 bytes, the focused Marcus context 11,528 bytes and the
shared council context 7,440 bytes. Full campaign state stayed unchanged by reads
and Annals navigation. Save/load produced identical memory; loading the earlier
save cleared the focused source, question and conversation. Foreign/raw-detail
stress fixtures were excluded, a stale reign date became unknown, missing legacy
history stayed safe, and an active practice battle withheld campaign memory.
The rendered ruler/source cards and standalone village were inspected. Both
native sessions exited cleanly, with no script errors or warnings.

Following explicit user approval, the Marcus/Lucius/Gaius persona changes were
uploaded to their existing private ElevenLabs agents. A fresh provider read-back
matched all three repository prompts exactly, preserved authentication and
privacy settings, and confirmed zero tools. This resolves the earlier automatic
approval block on transferring the new instructions. Existing configured voices
remain available; memory-conditioned native playback and subjective voice
quality have not been reverified. The previous synthetic headless audio-cleanup
warning was outside this change and was not rerun.

Verified by: data validation, Godot import, isolated native campaign/village walkthroughs and exact ElevenLabs prompt read-back with unchanged authentication/privacy. Tests: not run (weekly review policy).

## Successor's first council — October 10, 2026

`SuccessionCouncilRules` records one bounded handover at the end of the first
resolved season after the actual player leader changes. It runs after the
existing chronicle collects the succession; it never chooses or kills a ruler,
draws RNG, or issues policy or military commands. The 5,120-byte capture includes
at most six own war stances, six owned-city edicts, aggregate tax settings, the
treasury, chosen patron/progress and up to three memory entries plus one prior
reign summary. Omitted entries remain explicit and do not imply absence.

The optional `advisor_succession` field keeps a silent current-leader baseline,
the current handover and its pending/reviewed/dismissed/postponed invitation.
Creation, migration, season reconciliation and fixture construction all seed it.
Save validation checks bounded structures, dates and source shapes. Legacy saves
remain version 2 and do not reconstruct historical handovers. A response requires
the exact save-local ruler/turn key; duplicate or stale replies do nothing. The
next actual succession replaces this current-reign record without creating an
unbounded archive. No game-wide chat memory is introduced.

The panel uses the existing council page, authored portraits and live controller.
The successor invitation has priority over other optional advisor invitations,
but waits for battles, pending defense, turn presentation and Dispatch. Opening,
reading and selecting an agenda are presentation only; review/postpone/dismiss
change only the invitation record. Later replay labels the frozen season-close
facts separately from current visible reports. A retained divine choice still
does not identify its ruler, motive or continuing policy.

The live snapshot has one `succession_handover` and separately labelled
`current_situation`, with only unlocked speakers. The current shared limits
remain: three speaker turns, 60 requested words each, 720-character response cap,
45 seconds per speaker, 140 seconds total, 18,000-byte initial snapshot, no retry.
The existing private personas already support explicit council requests; an
authored runtime question supplies the new agenda without changing credentials
or provider configuration. Speaker switching, leaving, context invalidation and
loading preserve the established stop/reset behavior.

Native acceptance used an isolated old-age prerequisite, then actual seasonal
processing changed Appius Claudius to Manius Valerius. The 1,931-byte handover
included an actual confirmed Public Works receipt; the final council snapshot
was 6,353 bytes. Invitations waited through presentation, Dispatch, prepared
pending defense and a real practice battle worker. Postponement, dismissal,
replay, exact serialized file save/load, silent legacy baseline, malformed-field
rejection, earlier/different save resets and a second actual succession were
observed directly. No automatic provider connection or reading-induced game
mutation occurred.

The first walkthrough left the fresh-profile introduction open for its quiet
invitation assertion and used strict Dictionary equality across JSON numeric
types. Those two QA assertions were corrected in a focused follow-up: closing
the introduction exposed the quiet invitation, and canonical handover content
matched exactly after actual file save/load. Source review also fixed stale
individual-advisor questions and absence wording when all entries were omitted.
The final focused run reported zero failures and exited cleanly.

One explicit private council completed Marcus, Lucius and Gaius in order with
readable text and PCM playback, no overlapping audio and unchanged full campaign
state. Provider credentials were absent from the native child. The standalone
village's isolated render retained all 11 lessons, no successor hook/navigation/
invitation, no connection and unchanged state. Both native sessions exited
without script errors or warnings. Subjective voice quality is not asserted.

Visual review caught the successor heading leaving live captions below the
initial scroll position. The explicit Hear action now waits for layout, fits
the transcript to the guide viewport and reveals its speaker/status card.
Opening a page does not move the reading position. A focused native render
using the three observed replies verified active and completed caption layouts
above Stop/Mute, with no additional provider request or campaign mutation.

Verified by: data validation, Godot import, isolated native successor/save/load and village walkthroughs, and one complete three-speaker private council with PCM playback. Tests: not run (weekly review policy).
