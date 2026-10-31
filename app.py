"""
Counsel Search on Streamlit: multi-tenant contract search.

turbopuffer  one namespace per law firm, hybrid search, filters
Vault        AppRole login at runtime; the turbopuffer key, demo password and
             tenant list all come from Vault
Terraform    HCP Terraform writes the Vault config and the tenant list;
             "Sync tenants" in the sidebar makes turbopuffer match it

A personal hobby project. Every firm and contract is fictional.
"""

from __future__ import annotations

import hmac
import os
import re

import streamlit as st

st.set_page_config(page_title="Counsel Search", page_icon="⚖️", layout="wide")

# Streamlit Cloud keeps secrets in st.secrets; copy them into the environment
# so the modules below read config the same way locally and in the cloud.
try:
    for _k, _v in st.secrets.items():
        if isinstance(_v, (str, int, float)):
            os.environ.setdefault(_k, str(_v))
except Exception:
    pass

from legal import contracts, search  # noqa: E402
from legal.vault_client import VaultSession  # noqa: E402

ss = st.session_state
TPUF_SECRET = "turbopuffer"      # {api_key, demo_password}, written by hand
CONFIG_SECRET = "config"         # {firms: {slug: name}}, written by Terraform

st.markdown("""
<style>
h1, h2, h3 {font-family: Georgia, "Source Serif 4", serif; letter-spacing: -.01em}
.clause {font-family: Georgia, serif; font-size: 1.15rem; font-weight: 600; margin-bottom: 0}
.meta {font-size: .82rem; opacity: .7; margin: 2px 0 6px}
.result mark {background: rgba(240, 200, 60, .35); color: inherit; padding: 0 1px; border-radius: 2px}
.result {border-bottom: 1px solid rgba(128,128,128,.25); padding: 10px 0 14px}
</style>""", unsafe_allow_html=True)


# ---------------------------------------------------------------------------
# Vault
# ---------------------------------------------------------------------------
@st.cache_resource
def vault() -> VaultSession:
    """One Vault session per running app, shared by all browser sessions."""
    need = ["VAULT_ADDR", "VAULT_ROLE_ID", "VAULT_SECRET_ID"]
    missing = [k for k in need if not os.getenv(k)]
    if missing:
        st.error(f"Missing {', '.join(missing)} in Streamlit Secrets (see .streamlit/secrets.toml.example).")
        st.stop()
    return VaultSession(
        addr=os.environ["VAULT_ADDR"],
        namespace=os.getenv("VAULT_NAMESPACE", "admin"),
        auth_path=os.getenv("VAULT_AUTH_PATH", "approle-legal-search"),
        role_id=os.environ["VAULT_ROLE_ID"],
        secret_id=os.environ["VAULT_SECRET_ID"],
        kv_mount=os.getenv("VAULT_KV_MOUNT", "legal-search-st"),
        refresh_seconds=int(os.getenv("SECRET_REFRESH_SECONDS", "120")),
    )


def tpuf_call(fn):
    """Run fn(tpuf_client). On a 401 the key was rotated: re-read it from Vault and retry once."""
    try:
        return fn(search.client(vault().read(TPUF_SECRET)["api_key"]))
    except Exception as e:
        if not search.is_auth_error(e):
            raise
        return fn(search.client(vault().read(TPUF_SECRET, force=True)["api_key"]))


def firms() -> dict[str, str]:
    return dict(vault().read(CONFIG_SECRET).get("firms", {}))


# ---------------------------------------------------------------------------
# Password gate (the shared password lives in Vault next to the key)
# ---------------------------------------------------------------------------
def password_gate():
    if ss.get("authed"):
        return
    st.title("Counsel Search")
    st.caption("A personal hobby project. Not affiliated with turbopuffer or HashiCorp.")
    expected = vault().read(TPUF_SECRET).get("demo_password")
    if not expected:
        ss["authed"] = True
        return
    with st.form("login"):
        entered = st.text_input("Demo password", type="password", help="Stored in Vault next to the turbopuffer key.")
        if st.form_submit_button("Enter"):
            if hmac.compare_digest(entered.encode(), str(expected).encode()):
                ss["authed"] = True
                st.rerun()
            st.error("That's not it.")
    st.stop()


def highlight(text: str, q: str) -> str:
    import html

    out = html.escape(text)
    for w in set(re.findall(r"[a-z0-9]{4,}", q.lower())):
        out = re.sub(rf"\b({re.escape(w)}\w*)", r"<mark>\1</mark>", out, flags=re.I)
    return out


# ---------------------------------------------------------------------------
# Sidebar: Vault status and tenant sync
# ---------------------------------------------------------------------------
def sidebar():
    v = vault()
    with st.sidebar:
        st.subheader("Vault")
        for k, val in v.status(TPUF_SECRET).items():
            st.markdown(f"<small>**{k}** · `{val}`</small>", unsafe_allow_html=True)
        if st.button("Re-read key now", use_container_width=True):
            v.read(TPUF_SECRET, force=True)
            v.read(CONFIG_SECRET, force=True)
            st.rerun()

        st.divider()
        st.subheader("Tenants")
        cfg = v.status(CONFIG_SECRET)
        st.caption(f"Firm list from `{cfg['Secret']}` v{cfg['Version']}, written by HCP Terraform.")
        wanted = {search.namespace_for(s): n for s, n in firms().items()}
        live = set(tpuf_call(search.live_namespaces))
        to_add = [ns for ns in wanted if ns not in live]
        to_remove = sorted(live - set(wanted))
        for ns in sorted(set(wanted) | live):
            badge = "🟢 live" if ns in live and ns in wanted else ("➕ to seed" if ns in wanted else "➖ to delete")
            st.markdown(f"<small>`{ns}` {badge}</small>", unsafe_allow_html=True)
        if to_add or to_remove:
            st.caption(f"Plan: seed {len(to_add)}, delete {len(to_remove)}")
            if st.button("Sync with Terraform", type="primary", use_container_width=True):
                slug_of = {search.namespace_for(s): s for s in firms()}
                for ns in to_add:
                    n = tpuf_call(lambda t, s=slug_of[ns]: search.seed(t, s))
                    st.toast(f"Seeded {ns} ({n} clauses)")
                for ns in to_remove:
                    tpuf_call(lambda t, n=ns: search.delete(t, n))
                    st.toast(f"Deleted {ns}")
                st.rerun()
        else:
            st.caption("turbopuffer matches Terraform. ✓")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
password_gate()
sidebar()

st.title("Counsel Search")
st.caption("Multi-tenant contract search · turbopuffer + HCP Vault + HCP Terraform · fictional firms, hobby demo")

all_firms = firms()
if not all_firms:
    st.info("No firms yet. Add some to `terraform.tfvars` and run the HCP Terraform workspace.")
    st.stop()

c1, c2, c3, c4 = st.columns([2, 1.3, 1.3, 1])
slug = c1.selectbox("Law firm (tenant)", list(all_firms), format_func=lambda s: all_firms[s])
ctype = c2.selectbox("Contract type", ["Any"] + contracts.CONTRACT_TYPES)
law = c3.selectbox("Governing law", ["Any"] + contracts.GOVERNING_LAW)
year = c4.number_input("Signed in or after", min_value=0, max_value=2026, value=0, step=1,
                       help="0 means any year")
mode = st.segmented_control("Search mode", ["Hybrid", "Vector", "BM25"], default="Hybrid") or "Hybrid"

ex = st.pills("Examples", contracts.EXAMPLE_QUESTIONS, label_visibility="collapsed")
q = st.text_input("Question", value=ex or "", placeholder="What's our liability cap and what's excluded?")

if q:
    filters = search.build_filters(None if ctype == "Any" else ctype, None if law == "Any" else law, year or None)
    try:
        res = tpuf_call(lambda t: search.search(t, slug, q, mode, filters))
    except Exception as e:
        if "not found" in str(e).lower() or getattr(e, "status_code", None) == 404:
            st.warning("This firm's namespace doesn't exist yet. Press **Sync with Terraform** in the sidebar.")
            st.stop()
        raise

    left, right = st.columns([3, 1.2])
    with right:
        st.metric("turbopuffer round trip", f"{res['ms']} ms")
        st.caption(f"Server {res['server_ms'] or '–'} ms · cache {res['cache'] or '–'} · "
                   f"namespace `{search.namespace_for(slug)}`")
        with st.expander("SDK call"):
            st.code(res["code"], language="python")
    with left:
        if not res["rows"]:
            st.info("No clauses matched. Try loosening the filters.")
        for r in res["rows"]:
            body = re.sub(r"^[^.]+\.\s*", "", r.get("content", ""))
            st.markdown(
                f"<div class='result'><p class='clause'>{r.get('clause')}</p>"
                f"<div class='meta'><b>{r.get('contract_type')}</b> · {r.get('counterparty')} · "
                f"{r.get('governing_law')} law · signed {r.get('signed_year')} · {r.get('matter')}</div>"
                f"{highlight(body, q)}</div>", unsafe_allow_html=True)

st.caption("A personal hobby project. Not affiliated with turbopuffer or HashiCorp. All firms and contracts are invented.")
