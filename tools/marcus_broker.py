#!/usr/bin/env python3
"""Local, native-client-only gateway to a private ElevenLabs Marcus agent.

Provider credentials stay in this process. Never publish, reverse proxy, or
package this development broker as a production authentication service.
"""

from __future__ import annotations

import argparse
import base64
from collections import deque
from dataclasses import dataclass, field
import getpass
import hmac
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import socket
import stat
import subprocess
import sys
import threading
import time
from typing import Callable, Mapping
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, urlencode, urlsplit
from urllib.request import HTTPRedirectHandler, ProxyHandler, Request, build_opener


HOST = "127.0.0.1"
PORT = 2270
BROKER_URL = f"http://{HOST}:{PORT}"
UPSTREAM = "https://api.elevenlabs.io/v1/convai"
MAX_BODY_BYTES = 128
MAX_PROVIDER_BYTES = 1_048_576
CLIENT_TIMEOUT_SECONDS = 5
UPSTREAM_TIMEOUT_SECONDS = 10
MAX_HTTP_WORKERS = 4
MAX_UPSTREAM_WORKERS = 2
SESSIONS_PER_MINUTE = 6
MAX_CREDENTIAL_BYTES = 8192


def private_credentials(path: str) -> dict[str, str]:
    """Read a user-selected private JSON file; never execute it as shell code."""
    location = Path(path).expanduser().absolute()
    repo = Path(__file__).resolve().parent.parent
    try:
        resolved = location.resolve(strict=True)
        if resolved == repo or repo in resolved.parents:
            raise ConfigurationError("Keep the credential file outside the game repository.")
        flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0)
        descriptor = os.open(location, flags)
        with os.fdopen(descriptor, "rb") as source:
            info = os.fstat(source.fileno())
            if not stat.S_ISREG(info.st_mode):
                raise ConfigurationError("The credential file must be a regular private file.")
            if os.name == "posix" and (info.st_uid != os.getuid() or info.st_mode & 0o077):
                raise ConfigurationError("The credential file must belong to you with owner-only permissions (chmod 600).")
            body = source.read(MAX_CREDENTIAL_BYTES + 1)
        if len(body) > MAX_CREDENTIAL_BYTES:
            raise ConfigurationError("The credential file is too large.")
        def unique_fields(pairs):
            result = {}
            for key, value in pairs:
                if key in result:
                    raise ValueError("duplicate field")
                result[key] = value
            return result
        values = json.loads(body, object_pairs_hook=unique_fields)
        allowed = {"ELEVENLABS_API_KEY", "ELEVENLABS_AGENT_ID", "ELEVENLABS_LUCIUS_AGENT_ID", "ELEVENLABS_GAIUS_AGENT_ID"}
        if (not isinstance(values, dict) or set(values) - allowed
                or not values.get("ELEVENLABS_API_KEY")
                or any(not isinstance(value, str) or not value for value in values.values())):
            raise ValueError("invalid fields")
        return values
    except ConfigurationError:
        raise
    except (OSError, ValueError, UnicodeError):
        raise ConfigurationError("Cannot read a valid private credential JSON file; no file contents were logged.") from None


class ConfigurationError(ValueError):
    """Contains safe field descriptions, never configuration values."""


class BrokerError(Exception):
    def __init__(self, status: int, code: str):
        self.status = status
        self.code = code
        super().__init__(code)


@dataclass(frozen=True)
class Config:
    token: str = field(repr=False)
    api_key: str = field(default="", repr=False)
    agent_id: str = field(default="", repr=False)
    lucius_agent_id: str = field(default="", repr=False)
    gaius_agent_id: str = field(default="", repr=False)

    def agent_for(self, advisor: str) -> str:
        agents = {"marcus": self.agent_id, "lucius": self.lucius_agent_id, "gaius": self.gaius_agent_id}
        if advisor not in agents:
            raise BrokerError(400, "unknown_advisor")
        selected = agents[advisor]
        if not self.api_key or not selected or sum(value == selected for value in agents.values()) > 1:
            raise BrokerError(503, "provider_not_configured")
        return selected

    @property
    def configured(self) -> bool:
        return bool(self.api_key and self.agent_id)

    @classmethod
    def from_environment(cls, env: Mapping[str, str]) -> "Config":
        token = env.get("MARCUS_BROKER_TOKEN", "")
        # Require at least a 256-bit, base64url-encoded random token. Structure
        # alone cannot prove entropy; --launch creates it using secrets.
        if not re.fullmatch(r"[A-Za-z0-9_-]{43,128}", token) or len(set(token)) < 16:
            raise ConfigurationError(
                "MARCUS_BROKER_TOKEN must be a random base64url token of at least "
                "32 bytes; use --launch to create one without displaying it."
            )
        try:
            token_bytes = base64.urlsafe_b64decode(token + "=" * (-len(token) % 4))
        except ValueError:
            raise ConfigurationError("MARCUS_BROKER_TOKEN has an invalid base64url format.") from None
        if len(token_bytes) < 32:
            raise ConfigurationError("MARCUS_BROKER_TOKEN is too short.")
        key = env.get("ELEVENLABS_API_KEY", "")
        agent = env.get("ELEVENLABS_AGENT_ID", "")
        if key and not re.fullmatch(r"[!-~]{1,512}", key):
            raise ConfigurationError("ELEVENLABS_API_KEY has an invalid format.")
        if agent and not re.fullmatch(r"[A-Za-z0-9_-]{1,128}", agent):
            raise ConfigurationError("ELEVENLABS_AGENT_ID has an invalid format.")
        lucius = env.get("ELEVENLABS_LUCIUS_AGENT_ID", "")
        if lucius and not re.fullmatch(r"[A-Za-z0-9_-]{1,128}", lucius):
            raise ConfigurationError("ELEVENLABS_LUCIUS_AGENT_ID has an invalid format.")
        if lucius and lucius == agent:
            raise ConfigurationError("Lucius requires a different private agent from Marcus.")
        gaius = env.get("ELEVENLABS_GAIUS_AGENT_ID", "")
        if gaius and not re.fullmatch(r"[A-Za-z0-9_-]{1,128}", gaius):
            raise ConfigurationError("ELEVENLABS_GAIUS_AGENT_ID has an invalid format.")
        if gaius and gaius in (agent, lucius):
            raise ConfigurationError("Gaius requires a distinct private agent.")
        return cls(token=token, api_key=key, agent_id=agent, lucius_agent_id=lucius, gaius_agent_id=gaius)


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # Never forward the xi-api-key credential to a redirected destination.
        return None


class ElevenLabs:
    def __init__(self, config: Config):
        self.config = config
        # Ignore proxy environment variables: the only destination is the
        # documented HTTPS API, with Python's default certificate validation.
        self.opener = build_opener(ProxyHandler({}), NoRedirect())

    def _get(self, path: str) -> dict:
        request = Request(
            UPSTREAM + path,
            headers={"xi-api-key": self.config.api_key, "Accept": "application/json"},
            method="GET",
        )
        try:
            with self.opener.open(request, timeout=UPSTREAM_TIMEOUT_SECONDS) as response:
                body = response.read(MAX_PROVIDER_BYTES + 1)
                if len(body) > MAX_PROVIDER_BYTES:
                    raise BrokerError(502, "provider_response_invalid")
                value = json.loads(body)
                if not isinstance(value, dict):
                    raise BrokerError(502, "provider_response_invalid")
                return value
        except HTTPError as error:
            # Do not read, return, or log upstream error bodies/URLs.
            error.close()
            raise BrokerError(502, "provider_request_failed") from None
        except (URLError, TimeoutError, OSError):
            raise BrokerError(502, "provider_unavailable") from None
        except (ValueError, UnicodeError):
            raise BrokerError(502, "provider_response_invalid") from None

    def create_session(self, advisor: str = "marcus") -> str:
        agent_id = self.config.agent_for(advisor)
        # Verify on EVERY mint, so a later accidental dashboard change from
        # private to public does not silently weaken the intended setup.
        agent = self._get("/agents/" + agent_id)
        settings = agent.get("platform_settings")
        auth = settings.get("auth") if isinstance(settings, dict) else None
        if (
            not isinstance(auth, dict)
            or auth.get("enable_auth") is not True
            or auth.get("allowlist") not in (None, [])
        ):
            raise BrokerError(503, "agent_must_require_authentication")
        query = urlencode(
            {"agent_id": agent_id, "include_conversation_id": "true"}
        )
        result = self._get("/conversation/get-signed-url?" + query)
        signed_url = result.get("signed_url")
        if not isinstance(signed_url, str) or len(signed_url) > 16_384:
            raise BrokerError(502, "provider_response_invalid")
        try:
            parsed = urlsplit(signed_url)
            query_values = parse_qs(parsed.query, strict_parsing=True)
            valid = (
                parsed.scheme == "wss"
                and parsed.netloc == "api.elevenlabs.io"
                and parsed.path == "/v1/convai/conversation"
                and not parsed.fragment
                and query_values.get("agent_id") == [agent_id]
                and len(query_values.get("conversation_signature", [])) == 1
                and bool(query_values["conversation_signature"][0])
                and not any(ord(char) < 33 or ord(char) > 126 for char in signed_url)
            )
        except ValueError:
            valid = False
        if not valid:
            raise BrokerError(502, "provider_response_invalid")
        return signed_url


class SessionGate:
    def __init__(self, clock: Callable[[], float] = time.monotonic):
        self.clock = clock
        self.lock = threading.Lock()
        self.attempts: deque[float] = deque()
        self.active = threading.BoundedSemaphore(MAX_UPSTREAM_WORKERS)

    def enter(self) -> None:
        with self.lock:
            now = self.clock()
            while self.attempts and self.attempts[0] <= now - 60:
                self.attempts.popleft()
            if len(self.attempts) >= SESSIONS_PER_MINUTE:
                raise BrokerError(429, "session_rate_limited")
            if not self.active.acquire(blocking=False):
                raise BrokerError(503, "broker_busy")
            self.attempts.append(now)

    def leave(self) -> None:
        self.active.release()


class BrokerServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = False
    request_queue_size = MAX_HTTP_WORKERS

    def __init__(self, config: Config, *, port: int = PORT):
        self.config = config
        self.provider = ElevenLabs(config)
        self.gate = SessionGate()
        self.http_workers = threading.BoundedSemaphore(MAX_HTTP_WORKERS)
        # No host override. Alternate ephemeral ports are only used by the
        # isolated security check; the CLI always binds 127.0.0.1:2270.
        super().__init__((HOST, port), BrokerHandler)

    @property
    def expected_host(self) -> str:
        return f"{HOST}:{self.server_port}"

    def get_request(self):
        sock, address = super().get_request()
        sock.settimeout(CLIENT_TIMEOUT_SECONDS)
        return sock, address

    def process_request(self, request, client_address):
        if not self.http_workers.acquire(blocking=False):
            self.shutdown_request(request)
            return
        try:
            super().process_request(request, client_address)
        except BaseException:
            self.http_workers.release()
            raise

    def process_request_thread(self, request, client_address):
        try:
            super().process_request_thread(request, client_address)
        finally:
            self.http_workers.release()

    def handle_error(self, request, client_address):
        # Default socketserver errors print tracebacks with request context.
        # This boundary deliberately emits no request or credential logs.
        pass


class BrokerHandler(BaseHTTPRequestHandler):
    server: BrokerServer
    protocol_version = "HTTP/1.0"
    server_version = "MarcusLocal"
    sys_version = ""

    def log_message(self, format, *args):
        pass

    def send_error(self, code, message=None, explain=None):
        self._reply(code, {"error": "invalid_request"})

    def _reply(self, status: int, value: dict):
        body = json.dumps(value, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Pragma", "no-cache")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)
        self.close_connection = True

    def _boundary(self):
        # Native Godot supplies no Origin. Reject ALL browser origins, even
        # null and loopback: no CORS endpoint is provided by this broker.
        if (
            self.client_address[0] != HOST
            or self.headers.get_all("Host", []) != [self.server.expected_host]
            or self.headers.get_all("Origin", [])
            or self.headers.get_all("Transfer-Encoding", [])
        ):
            raise BrokerError(403, "request_not_allowed")

    def _authorize(self):
        values = self.headers.get_all("Authorization", [])
        supplied = values[0].encode("utf-8") if len(values) == 1 else b""
        expected = ("Bearer " + self.server.config.token).encode("ascii")
        if not hmac.compare_digest(supplied, expected):
            raise BrokerError(401, "authentication_required")

    def _advisor_request(self) -> str:
        lengths = self.headers.get_all("Content-Length", [])
        if len(lengths) != 1 or not re.fullmatch(r"[0-9]{1,4}", lengths[0]):
            raise BrokerError(400, "invalid_body")
        length = int(lengths[0])
        if length > MAX_BODY_BYTES:
            raise BrokerError(413, "body_too_large")
        types = self.headers.get_all("Content-Type", [])
        if types != ["application/json"]:
            raise BrokerError(415, "json_required")
        try:
            body = self.rfile.read(length)
            def unique_fields(pairs):
                result = {}
                for key, value in pairs:
                    if key in result:
                        raise ValueError("duplicate field")
                    result[key] = value
                return result
            request = json.loads(body, object_pairs_hook=unique_fields)
            if len(body) != length or not isinstance(request, dict) or set(request) - {"advisor"}:
                raise BrokerError(400, "invalid_body")
            advisor = request.get("advisor", "marcus")
            if advisor not in ("marcus", "lucius", "gaius"):
                raise BrokerError(400, "unknown_advisor")
            return advisor
        except (ValueError, UnicodeError):
            raise BrokerError(400, "invalid_body") from None

    def _handle(self):
        try:
            self._boundary()
            if self.command == "GET" and self.path == "/health":
                if self.headers.get_all("Content-Length", []) not in ([], ["0"]):
                    raise BrokerError(400, "invalid_body")
                self._reply(200, {"configured": self.server.config.configured})
                return
            if self.command != "POST" or self.path != "/session":
                raise BrokerError(404, "not_found")
            self._authorize()
            advisor = self._advisor_request()
            self.server.gate.enter()
            try:
                signed_url = self.server.provider.create_session(advisor)
            finally:
                self.server.gate.leave()
            self._reply(200, {"signed_url": signed_url})
        except BrokerError as error:
            self._reply(error.status, {"error": error.code})
        except (TimeoutError, socket.timeout):
            self._reply(408, {"error": "request_timeout"})
        except (BrokenPipeError, ConnectionResetError):
            self.close_connection = True
        except Exception:
            # Neither exception text nor provider values may cross the boundary.
            self._reply(500, {"error": "broker_error"})

    do_GET = _handle
    do_POST = _handle
    do_OPTIONS = _handle
    do_PUT = _handle
    do_DELETE = _handle
    do_PATCH = _handle


def child_environment(env: Mapping[str, str], token: str) -> dict[str, str]:
    child = {
        key: value
        for key, value in env.items()
        if not key.upper().startswith(("ELEVENLABS_", "OPENAI_", "ANTHROPIC_", "AZURE_OPENAI_"))
        and key.upper() not in ("XI_API_KEY", "MARCUS_BROKER_TOKEN", "MARCUS_BROKER_URL")
    }
    child["MARCUS_BROKER_TOKEN"] = token
    child["MARCUS_BROKER_URL"] = BROKER_URL
    return child


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--prompt-credentials", action="store_true",
        help="Prompt locally for missing ElevenLabs credentials; the key is hidden.",
    )
    parser.add_argument(
        "--credentials-file", metavar="PATH",
        help="Read provider settings from an owner-only JSON file outside the repository; never sent to Godot.",
    )
    parser.add_argument(
        "--campaign", action="store_true",
        help="Use the parent Roman campaign as the default --launch target.",
    )
    parser.add_argument(
        "--launch", nargs=argparse.REMAINDER, metavar="COMMAND",
        help="Generate a private token, run Godot with it, and stop when Godot exits. "
             "An optional command follows this final flag (default: the Yenikapi village project).",
    )
    args = parser.parse_args(argv)
    env = dict(os.environ)
    if args.campaign and args.launch is None:
        parser.error("--campaign requires --launch")
    if args.credentials_file:
        try:
            # An explicitly chosen file is authoritative for its provider fields.
            env.update(private_credentials(args.credentials_file))
        except ConfigurationError as error:
            print(str(error), file=sys.stderr)
            return 2
    if args.prompt_credentials:
        if not sys.stdin.isatty():
            print("Credential prompts require an interactive terminal.", file=sys.stderr)
            return 2
        if not env.get("ELEVENLABS_AGENT_ID"):
            env["ELEVENLABS_AGENT_ID"] = input("Private ElevenLabs agent id: ").strip()
        if not env.get("ELEVENLABS_API_KEY"):
            env["ELEVENLABS_API_KEY"] = getpass.getpass("ElevenLabs API key (hidden): ").strip()
    if args.launch is not None:
        env["MARCUS_BROKER_TOKEN"] = secrets.token_urlsafe(32)
    try:
        config = Config.from_environment(env)
    except (ConfigurationError, ValueError) as error:
        message = str(error) if isinstance(error, ConfigurationError) else "Invalid broker token format."
        print(message, file=sys.stderr)
        return 2
    try:
        server = BrokerServer(config)
    except OSError:
        print("Cannot bind Marcus broker to 127.0.0.1:2270; stop any existing broker first.", file=sys.stderr)
        return 2
    print(f"Marcus broker listening on {BROKER_URL}. Provider configured: {'yes' if config.configured else 'no'}.", flush=True)
    child = None
    if args.launch is not None:
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        repo = Path(__file__).resolve().parent.parent
        bundled_godot = repo / "build/constantinople-toolchain/Godot.app/Contents/MacOS/Godot"
        godot = shutil.which("godot") or (str(bundled_godot) if bundled_godot.is_file() else "godot")
        village = repo / "Castles and Cities/sites/yenikapi_6000_bce/experience"
        command = args.launch or [godot, "--path", str(repo if args.campaign else village)]
        try:
            child = subprocess.Popen(command, env=child_environment(env, config.token))
            return child.wait()
        except KeyboardInterrupt:
            return 130
        except OSError:
            print("Could not start Godot; supply its executable after --launch.", file=sys.stderr)
            return 2
        finally:
            if child is not None and child.poll() is None:
                child.terminate()
                try:
                    child.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait()
            server.shutdown()
            server.server_close()
            worker.join(timeout=2)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
