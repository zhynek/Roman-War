# Private voices for Marcus, Lucius and Gaius

October 10 memory phase: Marcus, Lucius and Gaius now have the source-backed
campaign-memory instructions in their existing private ElevenLabs agents.
Following explicit user approval, each uploaded prompt was read back and matched
its repository file exactly; authentication and privacy settings were unchanged,
with zero tools. This resolves the earlier automatic approval block. The
previously configured voices and broker are unchanged. The new memory page,
bounded context assembly and save/load path have been verified locally;
memory-conditioned native playback has not been rerun.

Live native verification completed October 9, 2026 after the user enabled
ElevenAgents Write (`convai_write`). Both Marcus and Lucius received private
sessions, streamed relevant text, and played PCM audio through Godot's native
AudioStreamPlayer. Muting immediately stopped playback; disconnecting cleared
the connection and audio buffer. Provider credentials were absent from the game
process. The authored guide, council and patronage also work offline.

The direct check used bounded campaign snapshots (8,396 and 9,424 bytes) with
Zeus pledged. Both advisors discussed the tax/order stewardship tradeoff. Replies
were deliberately interrupted after text and playback began to verify mute and
disconnect; this was a technical playback check, not a subjective voice-quality
review. No broad test suite was run. Read alone cannot mint these sessions.

Marcus's native Godot client obtains a temporary conversation URL from
`tools/marcus_broker.py`. Only that Python process holds the ElevenLabs API key.
ElevenLabs runs the configured LLM and voice together; the game does not need an
OpenAI or Anthropic key. There are no credentials in this repository.

This is a local development connection for one trusted computer. The broker
always binds `127.0.0.1:2270`. It is not a public deployment or a substitute for
player accounts, billing limits and a hosted authenticated service.

## Configured private agent

Created and published October 8, 2026:
[Marcus — Roman War Advisor](https://elevenlabs.io/app/agents/agents/agent_1001m4e1c02ee6p8n4jf0fcj5b6w/agent).
Its nonsecret agent ID is `agent_1001m4e1c02ee6p8n4jf0fcj5b6w`.

- LLM: Claude Sonnet 5, maximum 1,024 output tokens, default backup models.
- Voice: **Grandfather Joe — Gentle, warm & wise**, library voice
  `0lp4RIz96WD1RUtvEu3Q`; V4 Turbo, expressive mode off.
- Output: PCM 16 kHz. Voice mode remains enabled for typed questions with speech.
- Client events: `audio`, `interruption`, `user_transcript`, `agent_response`,
  `agent_response_correction`, `agent_chat_response_part`, `agent_response_complete`.
- Security: private authentication required, empty hostname allowlist, 30 daily
  conversations, two concurrent conversations, no bursting or call queuing.
- Privacy: zero-retention mode enabled, call audio recording off. ElevenLabs
  [documents that zero retention applies to API traffic](https://elevenlabs.io/docs/eleven-api/resources/zero-retention-mode),
  not dashboard previews.
- Attachments and speculative turns off; no spontaneous response after silence;
  maximum conversation duration 600 seconds. No tools configured.

GPT-6 Sol was rejected by the dashboard as incompatible with zero retention;
Claude Sonnet 5 was accepted with that protection enabled. These are provider
settings, not hardcoded client requirements; live acceptance is tracked above.

The published prompt now supports both `yenikapi_early_settlement` and
`roman_campaign`, including partial seasonal reports and the limited live
battle context. This prompt update does not establish native voice acceptance.

## Lucius governance agent

Created and published October 8, 2026:
[Lucius — Roman War Governance Advisor](https://elevenlabs.io/app/agents/agents/agent_2101m4eq0t7mfq38ap8prtxm6nqd/agent).
Nonsecret agent ID: `agent_2101m4eq0t7mfq38ap8prtxm6nqd`.
Its [governance prompt](../advisors/lucius-agent-prompt.txt) and greeting identify
an original fictional AI senator. Voice: **Declan Sage — Wise and Captivating**;
V4 Turbo, expressive mode off. It uses the same Claude Sonnet 5 configuration.

The dashboard confirmed private authentication, PCM 16 kHz, zero retention,
recording off, 30 daily calls, two concurrent calls, bursting and queuing off.
The settings were copied from Marcus, including client events and no tools.
Marcus's published prompt now recognizes Lucius and the actual council status.
Native playback for both configured voices was subsequently verified as described
above.

The broker maps `marcus` to `ELEVENLABS_AGENT_ID` and `lucius` to
`ELEVENLABS_LUCIUS_AGENT_ID`. Set both for the campaign. Missing Lucius config
fails clearly; it never falls back to Marcus. Equal agent IDs are rejected.
The unlock gates the game UI, not paid multiplayer entitlements; this local
broker trusts its authorized native process and does not validate saves.

## Gaius military agent and the living council

Created October 9, 2026 through the existing restricted key:
[Gaius — Roman War Military Counselor](https://elevenlabs.io/app/agents/agents/agent_3601m4gd7j2wfnatxtn3vykjkqmv/agent).
Nonsecret agent ID: `agent_3601m4gd7j2wfnatxtn3vykjkqmv`; stock **Adam** voice
`pNInz6obpgDQGcFmaJgB`, V4 Turbo, PCM 16 kHz. Its original
[military persona](../advisors/gaius-agent-prompt.txt) uses the same model,
private authentication, zero retention, no recording, no tools and account limits
as the other advisors. No key was replaced or permission broadened.

The existing owner-only private JSON now contains `ELEVENLABS_GAIUS_AGENT_ID`
alongside the other provider fields. The broker allowlists this identity and
rejects missing or duplicate IDs; it never substitutes Marcus or Lucius.
The double-click launcher needs no additional setup on this computer.

All three provider prompts were updated and read back to match the repository's
council and dilemma instructions while preserving privacy/authentication settings.
The explicit council opens at most one connection per unlocked speaker, one
question per connection, with no retries. Introductions are muted; the bounded
answer plays sequentially with labelled text. Cancellation closes the transport.
The existing local session rate limit of six attempts per minute still applies.

The subsequent isolated native council completed all three speakers using a
7,530-byte frozen campaign snapshot. Marcus, Lucius and Gaius produced readable
294/377/404-character replies and sequential PCM playback, with no overlapping
audio or campaign-state changes. A second explicit discussion verified mute and
context-change cancellation. Offline fallback retained the authored council.
These are technical playback observations; voice character and pacing still
need the player's listening review.

The live provider omitted `agent_response_complete` for both greetings and
questions despite that event being enabled. The client now accepts the documented
final `agent_response` for these tool-free advisors, retains streamed text, and
waits for queued PCM/playback plus a 500 ms settling interval before advancing.
Late and interrupted text/audio retain their response-ID/event-ID safeguards.
The focused regression uses synthetic events and no credentials. It passed,
with one retained `AudioStreamGeneratorPlayback` warning at headless teardown;
the real campaign and standalone village sessions exited cleanly.

## Recreate or change the agent

In the ElevenLabs dashboard, create a dedicated Marcus agent and configure its
prompt, first message, knowledge and voice using
[`agent-prompt.txt`](agent-prompt.txt) and [`../MARCUS_ADVISOR.md`](../MARCUS_ADVISOR.md).
Enable authentication in the agent Security settings. The API representation is
`platform_settings.auth.enable_auth: true`; `requires_auth` is the SDK option,
not the dashboard/API field. Leave the hostname allowlist empty. The broker
checks this configuration again before every session and refuses public agents.

Use an ElevenLabs API key with permission to read that agent and generate
conversation signed URLs. ElevenLabs requires ElevenAgents Write for signed URL
generation, even though that endpoint uses GET. Keep the key in a secret manager, a protected local
environment, or the hidden terminal prompt below. A key saved as a GitHub Actions
secret is available to authorized Actions jobs, not retrievable by this local
game. Never add a key to an agent prompt, JSON content, a Godot setting, a save,
an export, a screenshot, a command argument or Git history.

Official references:

- [Agent authentication](https://elevenlabs.io/docs/eleven-agents/customization/authentication)
- [Get agent configuration](https://elevenlabs.io/docs/api-reference/agents/get)
- [Generate a signed conversation URL](https://elevenlabs.io/docs/api-reference/conversations/get-signed-url)

## Launch safely

On the configured computer, double-click
[`Launch Roman War Advisors.command`](../../Launch%20Roman%20War%20Advisors.command).
It starts the parent campaign and local broker using:

```sh
python3 tools/marcus_broker.py \
  --credentials-file "$HOME/Library/Application Support/Roman War/private-advisors.json" \
  --campaign --launch
```

The JSON file contains the provider key and the two agent IDs. It is outside the
repository in an owner-only directory (0700), with owner-only file permissions
(0600). The loader rejects repository paths, symlinks, shared permissions, unknown
fields, duplicates and oversized files. No shell evaluation is used. The user also
requested a private backup in `Folder_Save.rtf` in iCloud TextEdit; existing notes
were preserved and its local file permissions were restricted to 0600. Neither
file is included in exports or source control.

The dedicated key is named **Roman War — Private Advisors**, with a 10,000-credit
limit per refresh period and leaked-key auto-disable enabled. All unrelated API
endpoints are disabled. Permission status and live acceptance are recorded above.

For a different computer without this private file, the hidden terminal prompt
remains available. The following command opens the standalone village:

From the repository directory, run:

```sh
ELEVENLABS_AGENT_ID=agent_1001m4e1c02ee6p8n4jf0fcj5b6w python3 tools/marcus_broker.py --prompt-credentials --launch
```

The configured agent ID above is not a secret. The terminal hides the API key
as you type; without `ELEVENLABS_AGENT_ID`, it also asks for the private agent ID.
The broker generates a fresh random 256-bit local token, starts Godot and removes
ElevenLabs, OpenAI and Anthropic environment variables from the game process.
It passes only `MARCUS_BROKER_URL` and `MARCUS_BROKER_TOKEN` for the connection.
By default it opens the **Yenikapı — Early Settlement** project. Marcus is
also available in the parent Roman campaign with the explicit command below. It uses `godot` on `PATH`, or the existing
`build/constantinople-toolchain/Godot.app/Contents/MacOS/Godot` binary when
available. The broker exits when the game closes. Nothing is written to disk by
this tool.

For the **Roman campaign**, supply the parent project path (the key still stays
in the broker, and the launcher still exits when the game closes):

```sh
ELEVENLABS_AGENT_ID=agent_1001m4e1c02ee6p8n4jf0fcj5b6w \
ELEVENLABS_LUCIUS_AGENT_ID=agent_2101m4eq0t7mfq38ap8prtxm6nqd \
python3 tools/marcus_broker.py --prompt-credentials --launch build/constantinople-toolchain/Godot.app/Contents/MacOS/Godot --path .
```

To specify the village project and Godot executable explicitly:

```sh
python3 tools/marcus_broker.py --prompt-credentials --launch build/constantinople-toolchain/Godot.app/Contents/MacOS/Godot --path "Castles and Cities/sites/yenikapi_6000_bce/experience"
```

Alternatively, supply `ELEVENLABS_API_KEY` and `ELEVENLABS_AGENT_ID` using your
local secret manager and omit `--prompt-credentials`. Without these values, the
launcher still opens the game, but live session requests return
`provider_not_configured`; the authored tutorial can remain available offline.
Running the broker without `--launch` requires a separately generated random
`MARCUS_BROKER_TOKEN` of at least 32 bytes encoded as base64url, shared privately
with the native game. The launcher is the recommended path.

## Native client contract

`POST http://127.0.0.1:2270/session` requires:

```text
Authorization: Bearer <MARCUS_BROKER_TOKEN>
Content-Type: application/json

{"advisor":"lucius"}
```

Only `marcus`, `lucius` or `gaius` is accepted. An empty object remains compatible with
older Marcus clients. Unknown identities, duplicate fields, extra fields,
arbitrary agent IDs and URLs are rejected.

A successful response is `{"signed_url":"wss://api.elevenlabs.io/..."}`.
Treat the whole URL as a temporary credential: use it only for the WebSocket
connection, never log or persist it. The broker requests
`include_conversation_id=true` to make the signature single-use. Start the
connection promptly; ElevenLabs documents a 15-minute connection window.

`GET /health` returns only `{"configured":true}` or `{"configured":false}`;
this means Marcus values are present, not that any agent was verified.
Every response is `Cache-Control: no-store`. Error responses contain a fixed
machine-readable `error` code, never a provider response, API key or agent ID.

All browser `Origin` headers, nonliteral loopback Host headers, query-string
routes, duplicate authentication headers, transfer encoding and arbitrary
provider overrides are refused. Requests are limited to 128 body bytes, six session
attempts per minute, two concurrent provider operations and four HTTP workers.
Provider requests use a fixed HTTPS origin, certificate validation, no redirects
and a ten-second socket timeout; proxy environment variables are ignored.
Missing or ambiguous agent authentication fails closed. No request logging,
CORS support or endpoint selection by clients is implemented.

Local authentication protects against browser pages and accidental network
exposure; processes already able to inspect the game process under your OS user
can also inspect its local token. Do not forward the port or distribute this
broker with a shared key. A released game needs its own hosted user/session
authorization and server-held provider credentials.

## Focused credential check

```sh
python3 tools/test_marcus_broker.py
```

This isolated security check uses synthetic values and a loopback ephemeral port.
It never contacts ElevenLabs, spends provider credit or runs the campaign suite.
It is covered by the weekly testing policy's credential-handling exception.

Verified October 9, 2026: all 21 focused checks passed in 4.094 seconds,
including separate Lucius/Gaius routing, wrong-agent signed URLs, private-agent
requirements, duplicate selector rejection, child-process credential removal,
and the private-file boundary described above.
This verifies the local credential boundary with synthetic credentials, not a
live provider conversation. The broad game suite was not run under the weekly
review policy.
