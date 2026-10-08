#!/usr/bin/env python3
"""Focused credential-boundary checks; never contacts ElevenLabs or runs Godot."""

import contextlib
import http.client
import io
import json
import threading
import unittest
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.parse import parse_qs, urlsplit

from marcus_broker import (
    BROKER_URL, BrokerError, BrokerServer, Config, ConfigurationError,
    ElevenLabs, SessionGate, child_environment,
)


TOKEN = "abcdefghijklmnopqrstuvwxyz0123456789_ABCDEFG"
CONFIG = Config(token=TOKEN, api_key="synthetic-provider-key", agent_id="agent_synthetic")
SIGNED_URL = (
    "wss://api.elevenlabs.io/v1/convai/conversation?"
    "agent_id=agent_synthetic&conversation_signature=synthetic-session-token"
)


class FakeProvider:
    def __init__(self):
        self.calls = 0

    def create_session(self):
        self.calls += 1
        return SIGNED_URL


class LocalBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.server = BrokerServer(CONFIG, port=0)
        self.provider = FakeProvider()
        self.server.provider = self.provider
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)

    def request(self, method="POST", path="/session", body=b"{}", headers=None):
        defaults = [
            ("Host", self.server.expected_host),
            ("Authorization", "Bearer " + TOKEN),
            ("Content-Type", "application/json"),
            ("Content-Length", str(len(body))),
        ]
        supplied = defaults if headers is None else headers
        connection = http.client.HTTPConnection("127.0.0.1", self.server.server_port, timeout=2)
        try:
            connection.putrequest(method, path, skip_host=True, skip_accept_encoding=True)
            for name, value in supplied:
                connection.putheader(name, value)
            connection.endheaders(body)
            response = connection.getresponse()
            return response.status, dict(response.getheaders()), json.loads(response.read())
        finally:
            connection.close()

    def headers(self, **overrides):
        result = {
            "Host": self.server.expected_host,
            "Authorization": "Bearer " + TOKEN,
            "Content-Type": "application/json",
            "Content-Length": "2",
        }
        result.update(overrides)
        return [(name, value) for name, value in result.items() if value is not None]

    def test_health_exposes_only_local_configuration_presence(self):
        status, headers, body = self.request(
            "GET", "/health", b"", [("Host", self.server.expected_host)]
        )
        self.assertEqual((status, body), (200, {"configured": True}))
        self.assertEqual(headers["Cache-Control"], "no-store")
        self.assertNotIn("Access-Control-Allow-Origin", headers)
        self.assertEqual(self.provider.calls, 0)

    def test_missing_wrong_and_duplicate_bearer_never_mint(self):
        variants = [
            self.headers(Authorization=None),
            self.headers(Authorization="Bearer wrong"),
            self.headers(Authorization="Basic " + TOKEN),
            self.headers() + [("Authorization", "Bearer " + TOKEN)],
        ]
        for headers in variants:
            with self.subTest(headers_variant=variants.index(headers)):
                self.assertEqual(self.request(headers=headers)[0], 401)
        self.assertEqual(self.provider.calls, 0)

    def test_rebinding_and_every_browser_origin_are_denied(self):
        variants = [
            self.headers(Host="attacker.example"),
            self.headers(Host="localhost:" + str(self.server.server_port)),
            self.headers(Host=None),
            self.headers() + [("Host", self.server.expected_host)],
            self.headers(Origin="https://attacker.example"),
            self.headers(Origin="null"),
            self.headers(Origin="http://" + self.server.expected_host),
            self.headers(**{"Transfer-Encoding": "chunked"}),
        ]
        for headers in variants:
            with self.subTest(headers_variant=variants.index(headers)):
                self.assertEqual(self.request(headers=headers)[0], 403)
        self.assertEqual(self.provider.calls, 0)

    def test_only_empty_json_body_is_accepted(self):
        for body in (b'{"agent_id":"other"}', b'{"url":"https://other"}', b"[]", b"null", b"bad"):
            with self.subTest(body=body):
                self.assertEqual(self.request(body=body)[0], 400)
        self.assertEqual(self.request(body=b" " * 129)[0], 413)
        self.assertEqual(self.request(headers=self.headers(**{"Content-Type": "text/plain"}))[0], 415)
        self.assertEqual(self.request(headers=self.headers(**{"Content-Length": None}))[0], 400)
        self.assertEqual(self.request(headers=self.headers() + [("Content-Length", "2")])[0], 400)
        self.assertEqual(self.provider.calls, 0)

    def test_only_exact_post_session_route_can_mint(self):
        for method, path in (("GET", "/session"), ("OPTIONS", "/session"), ("POST", "/session?agent_id=other")):
            with self.subTest(method=method, path=path):
                self.assertEqual(self.request(method, path)[0], 404)
        self.assertEqual(self.provider.calls, 0)
        with contextlib.redirect_stderr(io.StringIO()) as errors:
            status, headers, body = self.request()
        self.assertEqual(status, 200)
        self.assertEqual(body, {"signed_url": SIGNED_URL})
        self.assertEqual(headers["Cache-Control"], "no-store")
        self.assertEqual(errors.getvalue(), "")
        self.assertEqual(self.provider.calls, 1)

    def test_global_session_rate_limit(self):
        for _ in range(6):
            self.assertEqual(self.request()[0], 200)
        self.assertEqual(self.request()[0], 429)
        self.assertEqual(self.provider.calls, 6)

    def test_unconfigured_and_unexpected_errors_are_safe(self):
        self.server.provider = ElevenLabs(Config(token=TOKEN))
        status, _, body = self.request()
        self.assertEqual((status, body), (503, {"error": "provider_not_configured"}))
        with patch.object(self.server.provider, "create_session", side_effect=RuntimeError(SIGNED_URL)):
            with contextlib.redirect_stderr(io.StringIO()) as errors:
                status, _, body = self.request()
        self.assertEqual((status, body), (500, {"error": "broker_error"}))
        self.assertEqual(errors.getvalue(), "")


class ProviderBoundaryTests(unittest.TestCase):
    def test_private_auth_is_checked_before_each_single_use_mint(self):
        provider = ElevenLabs(CONFIG)
        with patch.object(provider, "_get", side_effect=[
            {"platform_settings": {"auth": {"enable_auth": True, "allowlist": []}}},
            {"signed_url": SIGNED_URL},
            {"platform_settings": {"auth": {"enable_auth": False}}},
        ]) as upstream:
            self.assertEqual(provider.create_session(), SIGNED_URL)
            with self.assertRaises(BrokerError) as caught:
                provider.create_session()
            self.assertEqual(caught.exception.code, "agent_must_require_authentication")
            paths = [call.args[0] for call in upstream.call_args_list]
        self.assertEqual(paths[0], "/agents/agent_synthetic")
        self.assertEqual(paths[2], paths[0])
        self.assertEqual(parse_qs(urlsplit(paths[1]).query), {
            "agent_id": ["agent_synthetic"], "include_conversation_id": ["true"]
        })

    def test_missing_public_or_mixed_auth_configuration_fails_closed(self):
        configs = [
            {}, {"platform_settings": None}, {"platform_settings": {"auth": {}}},
            {"platform_settings": {"auth": {"enable_auth": "true"}}},
            {"platform_settings": {"auth": {"enable_auth": 1}}},
            {"platform_settings": {"auth": {"enable_auth": True, "allowlist": [{"hostname": "example.com"}]}}},
        ]
        for config in configs:
            with self.subTest(config=config):
                provider = ElevenLabs(CONFIG)
                with patch.object(provider, "_get", return_value=config) as upstream:
                    with self.assertRaises(BrokerError) as caught:
                        provider.create_session()
                    self.assertEqual(caught.exception.status, 503)
                    self.assertEqual(upstream.call_count, 1)

    def test_only_expected_provider_websocket_url_is_returned(self):
        invalid_urls = [
            SIGNED_URL.replace("wss://", "ws://"),
            SIGNED_URL.replace("api.elevenlabs.io", "attacker.example"),
            SIGNED_URL.replace("api.elevenlabs.io", "api.elevenlabs.io@attacker.example"),
            SIGNED_URL.replace("agent_synthetic", "agent_other"),
            SIGNED_URL.replace("conversation_signature", "other"),
            SIGNED_URL + "&conversation_signature=second",
            SIGNED_URL + "#fragment",
            SIGNED_URL + "\n",
            None,
        ]
        for url in invalid_urls:
            with self.subTest(url=url):
                provider = ElevenLabs(CONFIG)
                with patch.object(provider, "_get", side_effect=[
                    {"platform_settings": {"auth": {"enable_auth": True}}},
                    {"signed_url": url},
                ]):
                    with self.assertRaises(BrokerError) as caught:
                        provider.create_session()
                    self.assertEqual(caught.exception.code, "provider_response_invalid")

    def test_provider_error_body_and_url_are_never_exposed(self):
        provider = ElevenLabs(CONFIG)
        error = HTTPError(SIGNED_URL, 403, "synthetic private detail", {}, io.BytesIO(b"synthetic-private-body"))
        with patch.object(provider.opener, "open", side_effect=error) as upstream:
            with self.assertRaises(BrokerError) as caught:
                provider._get("/agents/agent_synthetic")
        self.assertEqual(str(caught.exception), "provider_request_failed")
        request = upstream.call_args.args[0]
        self.assertEqual(request.get_header("Xi-api-key"), CONFIG.api_key)
        self.assertEqual(request.full_url, "https://api.elevenlabs.io/v1/convai/agents/agent_synthetic")
        self.assertEqual(upstream.call_args.kwargs["timeout"], 10)

    def test_concurrency_and_rate_window_are_bounded(self):
        now = [0.0]
        gate = SessionGate(clock=lambda: now[0])
        gate.enter()
        gate.enter()
        with self.assertRaises(BrokerError) as caught:
            gate.enter()
        self.assertEqual(caught.exception.code, "broker_busy")
        gate.leave()
        gate.leave()
        for _ in range(4):
            gate.enter()
            gate.leave()
        with self.assertRaises(BrokerError) as caught:
            gate.enter()
        self.assertEqual(caught.exception.status, 429)
        now[0] = 60.0
        gate.enter()
        gate.leave()

    def test_launcher_strips_provider_credentials_and_replaces_old_session(self):
        source = {
            "PATH": "/bin", "ELEVENLABS_API_KEY": "secret", "ELEVENLABS_AGENT_ID": "agent",
            "OPENAI_API_KEY": "secret", "ANTHROPIC_AUTH_TOKEN": "secret",
            "AZURE_OPENAI_KEY": "secret", "XI_API_KEY": "secret",
            "MARCUS_BROKER_TOKEN": "old", "MARCUS_BROKER_URL": "http://other",
        }
        self.assertEqual(child_environment(source, TOKEN), {
            "PATH": "/bin", "MARCUS_BROKER_TOKEN": TOKEN, "MARCUS_BROKER_URL": BROKER_URL,
        })
        self.assertEqual(source["MARCUS_BROKER_TOKEN"], "old")

    def test_configuration_rejects_weak_tokens_and_header_injection(self):
        for token in ("", "replace-me", "a" * 43):
            with self.subTest(token=token):
                with self.assertRaises(ConfigurationError):
                    Config.from_environment({"MARCUS_BROKER_TOKEN": token})
        for name, value in (("ELEVENLABS_API_KEY", "key\r\nInjected: value"), ("ELEVENLABS_AGENT_ID", "../other")):
            with self.subTest(name=name):
                with self.assertRaises(ConfigurationError):
                    Config.from_environment({"MARCUS_BROKER_TOKEN": TOKEN, name: value})
        self.assertEqual(Config.from_environment({"MARCUS_BROKER_TOKEN": TOKEN}), Config(token=TOKEN))
        self.assertNotIn(TOKEN, repr(CONFIG))
        self.assertNotIn(CONFIG.api_key, repr(CONFIG))


if __name__ == "__main__":
    unittest.main(verbosity=2)
