#!/usr/bin/env python3
"""Serve the Atoll compatibility fixture on two loopback HTTPS origins."""

from __future__ import annotations

import argparse
import json
import mimetypes
import ssl
import threading
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlsplit


MAX_UPLOAD_BYTES = 16 * 1024 * 1024
SITE_ROOT = Path(__file__).resolve().parent / "site"


class FixtureHTTPServer(ThreadingHTTPServer):
    """Store fixture configuration beside the standard HTTP server state."""

    allow_reuse_address = True
    daemon_threads = True

    def __init__(
        self,
        address: tuple[str, int],
        *,
        role: str,
        primary_port: int,
        secondary_port: int,
        site_root: Path = SITE_ROOT,
    ) -> None:
        super().__init__(address, FixtureRequestHandler)
        self.fixture_role = role
        self.primary_port = primary_port
        self.secondary_port = secondary_port
        self.site_root = site_root.resolve()


class FixtureRequestHandler(BaseHTTPRequestHandler):
    """Serve static controls and small upload and download endpoints."""

    server: FixtureHTTPServer
    protocol_version = "HTTP/1.1"

    def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        self._handle_get(send_body=True)

    def do_HEAD(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        self._handle_get(send_body=False)

    def _handle_get(self, *, send_body: bool) -> None:
        path = urlsplit(self.path).path
        if path == "/health":
            self._send_json(
                {"status": "ok", "origin": self.server.fixture_role},
                send_body=send_body,
            )
            return
        if path == "/download":
            payload = b"Atoll compatibility fixture download.\n"
            self._send_bytes(
                payload,
                content_type="text/plain; charset=utf-8",
                extra_headers={
                    "Content-Disposition": 'attachment; filename="atoll-fixture.txt"'
                },
                send_body=send_body,
            )
            return

        route = "/index.html" if path == "/" else path
        self._serve_static(route, send_body=send_body)

    def do_POST(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        path = urlsplit(self.path).path
        if path != "/upload":
            self._send_error(HTTPStatus.NOT_FOUND, "Unknown fixture endpoint")
            return

        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            self._send_error(HTTPStatus.BAD_REQUEST, "Invalid Content-Length")
            return

        if length <= 0:
            self._send_error(HTTPStatus.BAD_REQUEST, "The upload is empty")
            return
        if length > MAX_UPLOAD_BYTES:
            self._send_error(HTTPStatus.REQUEST_ENTITY_TOO_LARGE, "The upload exceeds 16 MiB")
            return

        content_type = self.headers.get("Content-Type", "")
        if not content_type.lower().startswith("multipart/form-data"):
            self._send_error(HTTPStatus.UNSUPPORTED_MEDIA_TYPE, "Use multipart form data")
            return

        received = len(self.rfile.read(length))
        self._send_json({"status": "received", "receivedBytes": received})

    def log_message(self, format_string: str, *args: object) -> None:
        print(f"[{self.server.fixture_role}] {self.address_string()} {format_string % args}")

    def _serve_static(self, route: str, *, send_body: bool) -> None:
        relative = Path(unquote(route).lstrip("/"))
        candidate = (self.server.site_root / relative).resolve()
        try:
            candidate.relative_to(self.server.site_root)
        except ValueError:
            self._send_error(HTTPStatus.NOT_FOUND, "Unknown fixture file")
            return

        if not candidate.is_file():
            self._send_error(HTTPStatus.NOT_FOUND, "Unknown fixture file")
            return

        payload = candidate.read_bytes()
        if candidate.suffix.lower() in {".html", ".js"}:
            text = payload.decode("utf-8")
            text = text.replace("{{PRIMARY_ORIGIN}}", self._primary_origin())
            text = text.replace("{{SECONDARY_ORIGIN}}", self._secondary_origin())
            payload = text.encode("utf-8")

        content_type = mimetypes.guess_type(candidate.name)[0] or "application/octet-stream"
        if content_type.startswith("text/") or content_type in {
            "application/javascript",
            "application/json",
        }:
            content_type += "; charset=utf-8"
        self._send_bytes(payload, content_type=content_type, send_body=send_body)

    def _primary_origin(self) -> str:
        return f"https://localhost:{self.server.primary_port}"

    def _secondary_origin(self) -> str:
        return f"https://127.0.0.1:{self.server.secondary_port}"

    def _send_json(self, value: dict[str, object], *, send_body: bool = True) -> None:
        payload = json.dumps(value, separators=(",", ":")).encode("utf-8")
        self._send_bytes(
            payload,
            content_type="application/json; charset=utf-8",
            send_body=send_body,
        )

    def _send_error(self, status: HTTPStatus, message: str) -> None:
        payload = json.dumps({"status": "error", "message": message}).encode("utf-8")
        self._send_bytes(payload, status=status, content_type="application/json; charset=utf-8")

    def _send_bytes(
        self,
        payload: bytes,
        *,
        content_type: str,
        status: HTTPStatus = HTTPStatus.OK,
        extra_headers: dict[str, str] | None = None,
        send_body: bool = True,
    ) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header(
            "Content-Security-Policy",
            "default-src 'self'; "
            "script-src 'self'; "
            "style-src 'self'; "
            f"frame-src {self._primary_origin()} {self._secondary_origin()}; "
            "connect-src 'self'; media-src 'self' blob:; worker-src 'self'",
        )
        for key, value in (extra_headers or {}).items():
            self.send_header(key, value)
        self.end_headers()
        if send_body:
            self.wfile.write(payload)


def make_tls_server(
    host: str,
    port: int,
    *,
    role: str,
    primary_port: int,
    secondary_port: int,
    certificate: Path,
    key: Path,
) -> FixtureHTTPServer:
    server = FixtureHTTPServer(
        (host, port),
        role=role,
        primary_port=primary_port,
        secondary_port=secondary_port,
    )
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(certificate, key)
    server.socket = context.wrap_socket(server.socket, server_side=True)
    return server


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--certificate", type=Path, required=True)
    parser.add_argument("--key", type=Path, required=True)
    parser.add_argument("--primary-port", type=int, default=8443)
    parser.add_argument("--secondary-port", type=int, default=8444)
    return parser.parse_args()


def main() -> None:
    arguments = parse_arguments()
    primary = make_tls_server(
        "127.0.0.1",
        arguments.primary_port,
        role="primary",
        primary_port=arguments.primary_port,
        secondary_port=arguments.secondary_port,
        certificate=arguments.certificate,
        key=arguments.key,
    )
    secondary = make_tls_server(
        "127.0.0.1",
        arguments.secondary_port,
        role="secondary",
        primary_port=arguments.primary_port,
        secondary_port=arguments.secondary_port,
        certificate=arguments.certificate,
        key=arguments.key,
    )

    secondary_thread = threading.Thread(target=secondary.serve_forever, daemon=True)
    secondary_thread.start()
    print(f"Primary fixture:   https://localhost:{arguments.primary_port}")
    print(f"Secondary origin:  https://127.0.0.1:{arguments.secondary_port}")
    print("Press Control-C to stop the fixture.")

    try:
        primary.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        primary.shutdown()
        secondary.shutdown()
        primary.server_close()
        secondary.server_close()
        secondary_thread.join(timeout=2)


if __name__ == "__main__":
    main()
