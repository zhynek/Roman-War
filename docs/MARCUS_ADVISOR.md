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
the initial teaching material. The parent Roman campaign remains a separate
application; a later adapter will connect the same advisor design to that game.

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

Milestones 4–6 are future work. The first slice introduces no new temple,
worship, emperor succession, council, or civilization-expansion mechanics.

## Boundaries

- The advisor is presentation only. It cannot dispatch commands, purchase,
  adopt a rules profile, advance seasons, mutate saves, consume campaign RNG,
  or call the battle resolver. “Show me” navigates; the player acts.
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

## Proposed next phase: Marcus across the Roman campaign

After native voice acceptance, pursue milestone 4 as one bounded phase:

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
