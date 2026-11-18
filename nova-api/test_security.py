"""Security regression tests for NOVA-generated licenses and client sessions."""
import hashlib
import json
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

TEST_ROOT = Path(tempfile.mkdtemp(prefix="nova-api-test-"))
os.environ["NOVA_DATA"] = str(TEST_ROOT / "data")
os.environ["NOVA_PACKAGE_PASSWORDS"] = json.dumps(["nova-test-package-password-123456"])
sys.path.insert(0, str(Path(__file__).resolve().parent))
import server  # noqa: E402

server.app.config.update(TESTING=True)


class NovaLicenseTests(unittest.TestCase):
    def setUp(self):
        shutil.rmtree(TEST_ROOT / "data", ignore_errors=True)
        server._DB_INITIALIZED.clear()
        server.ADMIN_USERNAME = "nova-admin"
        server.ADMIN_PASSWORD = "test-only-password"
        self.client = server.app.test_client()
        response = self.client.post("/api/auth/login", json={"username": "nova-admin", "password": "test-only-password"})
        self.assertEqual(response.status_code, 200)

    def _generate(self, **overrides):
        payload = {"count": 1, "days": 0, "max_devices": 1, "note": "unit test"}
        payload.update(overrides)
        response = self.client.post("/api/admin/licenses", json=payload)
        self.assertEqual(response.status_code, 201, response.get_data(as_text=True))
        return response.get_json()["keys"][0]

    def test_admin_key_generation_stores_only_a_hash(self):
        key = self._generate()
        self.assertTrue(key.startswith("NOVA-"))
        conn = server.db()
        stored = conn.execute("SELECT key_hash,key_hint FROM licenses").fetchone()
        conn.close()
        self.assertEqual(stored["key_hash"], hashlib.sha256(key.encode()).hexdigest())
        self.assertNotEqual(stored["key_hash"], key)
        self.assertEqual(stored["key_hint"], key[-4:])

    def test_generated_key_binds_to_first_device_and_issues_patch_session(self):
        key = self._generate()
        device = "nova-device-00000001"
        response = self.client.post("/api/license/verify", json={"key": key, "device_id": device})
        self.assertEqual(response.status_code, 200, response.get_data(as_text=True))
        payload = response.get_json()
        self.assertTrue(payload["valid"])
        self.assertTrue(payload["client_session"])
        manifest = self.client.get("/api/patches", headers={"Authorization": f"Bearer {payload['client_session']}"})
        self.assertEqual(manifest.status_code, 200)
        self.assertEqual(manifest.get_json()["package_passwords"], ["nova-test-package-password-123456"])
        denied = self.client.post("/api/license/verify", json={"key": key, "device_id": "nova-device-00000002"})
        self.assertEqual(denied.status_code, 403)
        self.assertEqual(denied.get_json()["status"], "device_limit")

    def test_license_can_be_revoked_and_existing_session_is_removed(self):
        key = self._generate()
        activated = self.client.post("/api/license/verify", json={"key": key, "device_id": "nova-device-00000001"}).get_json()
        response = self.client.post("/api/admin/licenses/revoke", json={"key": key})
        self.assertEqual(response.status_code, 200)
        retry = self.client.post("/api/license/verify", json={"key": key, "device_id": "nova-device-00000001"})
        self.assertEqual(retry.status_code, 403)
        manifest = self.client.get("/api/patches", headers={"Authorization": f"Bearer {activated['client_session']}"})
        self.assertEqual(manifest.status_code, 401)

    def test_expiring_license_is_rejected(self):
        key = self._generate(days=1)
        conn = server.db()
        conn.execute("UPDATE licenses SET expires_at=1 WHERE key_hash=?", (hashlib.sha256(key.encode()).hexdigest(),))
        conn.commit(); conn.close()
        response = self.client.post("/api/license/verify", json={"key": key, "device_id": "nova-device-00000001"})
        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.get_json()["status"], "expired")

    def test_admin_routes_require_authentication(self):
        anonymous = server.app.test_client()
        self.assertEqual(anonymous.get("/api/admin/licenses").status_code, 401)
        self.assertEqual(anonymous.post("/api/admin/licenses", json={"count": 1}).status_code, 401)


def tearDownModule():
    shutil.rmtree(TEST_ROOT, ignore_errors=True)


if __name__ == "__main__":
    unittest.main()
