"""
Vault at runtime from Streamlit Community Cloud, using AppRole.

Streamlit Cloud gives the app no cloud identity it could prove to Vault (no
IAM role, no service account, no stable egress IP), so the app needs one
credential to start from: an AppRole role ID plus secret ID, kept in
Streamlit's Secrets. That's the "secret zero". Everything after it is
short-lived:

    role_id + secret_id ──login──▶ Vault token (15 min) ──read──▶ KV secrets (cached)

Rotating the turbopuffer key in Vault reaches the running app on its next
refresh, with no redeploy. On AWS, GCP or Kubernetes the role ID / secret ID
pair disappears and the app logs in with its platform identity instead (see
the tpuf-legal-search-aws repo).
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field

import hvac


@dataclass
class VaultSession:
    addr: str
    namespace: str
    auth_path: str
    role_id: str
    secret_id: str
    kv_mount: str
    refresh_seconds: int = 120
    _client: hvac.Client | None = None
    _token_expires: float = 0.0
    _token_ttl: int = 0
    logins: int = 0
    _cache: dict = field(default_factory=dict)   # path -> (data, metadata, read_at)

    def client(self) -> hvac.Client:
        """An authenticated client, logging in again a minute before the token expires."""
        if self._client and time.time() < self._token_expires - 60:
            return self._client
        c = hvac.Client(url=self.addr, namespace=self.namespace or None)
        auth = c.auth.approle.login(role_id=self.role_id, secret_id=self.secret_id,
                                    mount_point=self.auth_path)["auth"]
        self._client, self._token_ttl = c, auth["lease_duration"]
        self._token_expires = time.time() + auth["lease_duration"]
        self.logins += 1
        return c

    def read(self, path: str, force: bool = False) -> dict:
        """A KV v2 secret's data, cached for refresh_seconds."""
        hit = self._cache.get(path)
        if hit and not force and time.time() - hit[2] < self.refresh_seconds:
            return hit[0]
        res = self.client().secrets.kv.v2.read_secret_version(
            path=path, mount_point=self.kv_mount, raise_on_deleted_version=True)["data"]
        self._cache[path] = (res["data"], res["metadata"], time.time())
        return res["data"]

    def status(self, path: str) -> dict:
        """What the UI shows. Never includes secret values beyond a short key prefix."""
        now = time.time()
        hit = self._cache.get(path)
        data, meta, read_at = hit if hit else ({}, {}, None)
        key = data.get("api_key", "")
        return {
            "Auth": f"AppRole ({self.auth_path})",
            "Token TTL": f"{max(0, round(self._token_expires - now))}s of {self._token_ttl}s" if self._client else "–",
            "Logins": self.logins,
            "Secret": f"{self.kv_mount}/{path}",
            "Version": meta.get("version", "–"),
            "Written": (meta.get("created_time") or "–")[:19].replace("T", " "),
            "Read": f"{round(now - read_at)}s ago (refresh {self.refresh_seconds}s)" if read_at else "–",
            "Key": f"{key[:9]}…" if key else "–",
        }
