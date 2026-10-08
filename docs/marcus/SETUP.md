# Marcus private voice connection

Live credential status: pending. The secure local broker and native client are
implemented, but an authenticated ElevenLabs conversation has not yet been
verified in the native game. One dashboard text conversation succeeded and was
ended; it does not prove the native audio/text connection.

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
settings, not hardcoded client requirements; the live native connection remains
pending the private key and one end-to-end conversation.

The published prompt now supports both `yenikapi_early_settlement` and
`roman_campaign`, including partial seasonal reports and the limited live
battle context. This prompt update does not establish native voice acceptance.

## Recreate or change the agent

In the ElevenLabs dashboard, create a dedicated Marcus agent and configure its
prompt, first message, knowledge and voice using
[`agent-prompt.txt`](agent-prompt.txt) and [`../MARCUS_ADVISOR.md`](../MARCUS_ADVISOR.md).
Enable authentication in the agent Security settings. The API representation is
`platform_settings.auth.enable_auth: true`; `requires_auth` is the SDK option,
not the dashboard/API field. Leave the hostname allowlist empty. The broker
checks this configuration again before every session and refuses public agents.

Use an ElevenLabs API key with permission to read that agent and generate
conversation signed URLs. Keep it in your own secret manager, a protected local
environment, or the hidden terminal prompt below. A key saved as a GitHub Actions
secret is available to authorized Actions jobs, not retrievable by this local
game. Never add a key to an agent prompt, JSON content, a Godot setting, a save,
an export, a screenshot, a command argument or Git history.

Official references:

- [Agent authentication](https://elevenlabs.io/docs/eleven-agents/customization/authentication)
- [Get agent configuration](https://elevenlabs.io/docs/api-reference/agents/get)
- [Generate a signed conversation URL](https://elevenlabs.io/docs/api-reference/conversations/get-signed-url)

## Launch safely

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
ELEVENLABS_AGENT_ID=agent_1001m4e1c02ee6p8n4jf0fcj5b6w python3 tools/marcus_broker.py --prompt-credentials --launch build/constantinople-toolchain/Godot.app/Contents/MacOS/Godot --path .
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

`POST http://127.0.0.1:2270/session` requires exactly:

```text
Authorization: Bearer <MARCUS_BROKER_TOKEN>
Content-Type: application/json

{}
```

A successful response is `{"signed_url":"wss://api.elevenlabs.io/..."}`.
Treat the whole URL as a temporary credential: use it only for the WebSocket
connection, never log or persist it. The broker requests
`include_conversation_id=true` to make the signature single-use. Start the
connection promptly; ElevenLabs documents a 15-minute connection window.

`GET /health` returns only `{"configured":true}` or `{"configured":false}`;
this means local values are present, not that the account or agent was verified.
Every response is `Cache-Control: no-store`. Error responses contain a fixed
machine-readable `error` code, never a provider response, API key or agent ID.

All browser `Origin` headers, nonliteral loopback Host headers, query-string
routes, duplicate authentication headers, transfer encoding and request
overrides are refused. Requests are limited to 128 body bytes, six session
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

Verified October 8, 2026: all 14 focused checks passed in 3.604 seconds. The
initial sandbox invocation could not bind its loopback socket; the authorized
invocation with loopback access passed. This verifies the local credential
boundary, not a live provider conversation. The existing game suite was not run
under the weekly review policy.
