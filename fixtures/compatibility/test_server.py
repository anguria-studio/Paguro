"""Tests for the Paguro compatibility fixture server."""

from __future__ import annotations

import json
import threading
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from server import FixtureHTTPServer


class FixtureServerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.server = FixtureHTTPServer(
            ("127.0.0.1", 0),
            role="primary",
            primary_port=8443,
            secondary_port=8444,
        )
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.base_url = f"http://127.0.0.1:{cls.server.server_port}"

    @classmethod
    def tearDownClass(cls) -> None:
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join(timeout=2)

    def get(self, path: str):
        return urlopen(f"{self.base_url}{path}", timeout=2)

    def test_health_reports_the_server_role(self) -> None:
        with self.get("/health") as response:
            payload = json.load(response)
        self.assertEqual(payload, {"status": "ok", "origin": "primary"})

    def test_index_contains_each_compatibility_control(self) -> None:
        with self.get("/") as response:
            html = response.read().decode("utf-8")
        for control_id in (
            "page-notification",
            "destination-notification",
            "page-click-notification",
            "provider-probe-notification",
            "worker-notification",
            "increment-badge",
            "open-popup",
            "upload-input",
            "download-file",
            "start-camera",
            "start-microphone",
            "start-call",
            "camera-status",
            "microphone-status",
            "microphone-level",
            "call-status",
            "session-account-label",
            "session-marker",
            "session-marker-status",
            "prepare-diagnostics",
            "diagnostic-output",
            "simulate-process-failure",
        ):
            self.assertIn(f'id="{control_id}"', html)
        self.assertIn("https://127.0.0.1:8444/cross-origin.html", html)

    def test_provider_probe_control_uses_structured_data_without_a_url(self) -> None:
        with self.get("/app.js") as response:
            script = response.read().decode("utf-8")
        start = script.index('control("provider-probe-notification")')
        end = script.index('control("worker-notification")')
        handler = script[start:end]
        self.assertIn('workspaceId: "fixture-workspace"', handler)
        self.assertIn('id: "fixture-channel"', handler)
        self.assertNotIn("targetURL", handler)

    def test_page_click_control_uses_a_handler_without_destination_data(self) -> None:
        with self.get("/app.js") as response:
            script = response.read().decode("utf-8")
        start = script.index('control("page-click-notification")')
        end = script.index('control("provider-probe-notification")')
        handler = script[start:end]
        self.assertIn('notification.addEventListener("click"', handler)
        self.assertIn("/notification-destination.html?source=page-handler", handler)
        self.assertNotIn("data:", handler)

    def test_notification_destination_is_a_same_origin_static_page(self) -> None:
        with self.get("/notification-destination.html?source=notification") as response:
            html = response.read().decode("utf-8")
        self.assertIn('id="notification-destination-status"', html)
        self.assertIn("Destination opened", html)

    def test_download_has_an_attachment_filename(self) -> None:
        with self.get("/download") as response:
            self.assertEqual(
                response.headers["Content-Disposition"],
                'attachment; filename="paguro-fixture.txt"',
            )
            self.assertIn(b"Paguro compatibility fixture", response.read())

    def test_download_supports_a_head_request(self) -> None:
        request = Request(f"{self.base_url}/download", method="HEAD")
        with urlopen(request, timeout=2) as response:
            self.assertEqual(response.status, 200)
            self.assertEqual(response.read(), b"")
            self.assertEqual(
                response.headers["Content-Disposition"],
                'attachment; filename="paguro-fixture.txt"',
            )

    def test_upload_reports_the_received_byte_count(self) -> None:
        boundary = "PaguroBoundary"
        body = (
            f"--{boundary}\r\n"
            'Content-Disposition: form-data; name="file"; filename="probe.txt"\r\n'
            "Content-Type: text/plain\r\n\r\n"
            "probe\r\n"
            f"--{boundary}--\r\n"
        ).encode("utf-8")
        request = Request(
            f"{self.base_url}/upload",
            data=body,
            headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
            method="POST",
        )
        with urlopen(request, timeout=2) as response:
            payload = json.load(response)
        self.assertEqual(payload["status"], "received")
        self.assertEqual(payload["receivedBytes"], len(body))

    def test_static_route_cannot_leave_the_site_directory(self) -> None:
        with self.assertRaises(HTTPError) as context:
            self.get("/%2e%2e/server.py")
        self.assertEqual(context.exception.code, 404)


if __name__ == "__main__":
    unittest.main()
