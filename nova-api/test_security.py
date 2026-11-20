"""Security regression tests for NOVA-generated licenses and client sessions."""
import hashlib
from io import BytesIO
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

    def _client_package_session(self):
        key = self._generate()
        return self.client.post(
            "/api/license/verify",
            json={"key": key, "device_id": "nova-device-contract"},
        ).get_json()["client_session"]

    def _insert_patch(self, patch_id, game, bundle_id, category="nova", enabled=1, paused=0):
        conn = server.db()
        now = 1_700_000_000
        conn.execute(
            """INSERT INTO patches
               (id,name,owner,category,game,bundle_id,target_path,target_paths,filename,stored_filename,sha256,size,
                enabled,paused,version,image_filename,status_text,sort_order,created_at,updated_at)
               VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            (patch_id, patch_id, "nova", category, game, bundle_id, "", "[]", patch_id + ".3105",
             patch_id + ".3105", "a" * 64, 10, enabled, paused, "1.2", "", "READY", 1, now, now),
        )
        conn.commit(); conn.close()
        server.PATCH_DIR.mkdir(parents=True, exist_ok=True)
        (server.PATCH_DIR / (patch_id + ".3105")).write_bytes(b"3105PATCH\x00")

    def test_catalog_nova_filters_exact_bundle_and_default_excludes_it(self):
        token = self._client_package_session()
        self._insert_patch("nova-valid", "nova", server.NOVA_SELF_BUNDLE_ID)
        self._insert_patch("game-valid", "normal", "com.dts.freefireth", category="aim")
        headers = {"Authorization": f"Bearer {token}"}
        nova = self.client.get("/api/patches?catalog=nova", headers=headers)
        ordinary = self.client.get("/api/patches", headers=headers)
        self.assertEqual(nova.status_code, 200)
        self.assertEqual([p["id"] for p in nova.get_json()["all_patches"]], ["nova-valid"])
        self.assertEqual(ordinary.status_code, 200)
        self.assertEqual([p["id"] for p in ordinary.get_json()["all_patches"]], ["game-valid"])

    def test_upload_rejects_mismatched_nova_category_or_bundle(self):
        payload = {"id":"invalid-nova", "name":"Invalid NOVA", "game":"nova", "bundle_id":server.NOVA_SELF_BUNDLE_ID,
                   "category":"aim", "version":"1", "file":( BytesIO(b"3105PATCH\x00"), "bad.3105")}
        response = self.client.post("/api/admin/patches", data=payload, content_type="multipart/form-data")
        self.assertEqual(response.status_code, 400)
        payload["category"] = "nova"
        payload["bundle_id"] = "com.dts.freefireth"
        payload["file"] = (BytesIO(b"3105PATCH\x00"), "bad.3105")
        response = self.client.post("/api/admin/patches", data=payload, content_type="multipart/form-data")
        self.assertEqual(response.status_code, 400)

    def test_nova_download_requires_client_auth_and_returns_package(self):
        self._insert_patch("nova-download", "nova", server.NOVA_SELF_BUNDLE_ID)
        anonymous = server.app.test_client().get("/api/patches/nova-download/download")
        self.assertEqual(anonymous.status_code, 401)
        anonymous.close()
        token = self._client_package_session()
        response = self.client.get("/api/patches/nova-download/download", headers={"Authorization": f"Bearer {token}"})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data, b"3105PATCH\x00")
        response.close()

    def test_admin_routes_require_authentication(self):
        anonymous = server.app.test_client()
        self.assertEqual(anonymous.get("/api/admin/licenses").status_code, 401)
        self.assertEqual(anonymous.post("/api/admin/licenses", json={"count": 1}).status_code, 401)


def tearDownModule():
    shutil.rmtree(TEST_ROOT, ignore_errors=True)


if __name__ == "__main__":
    unittest.main()
