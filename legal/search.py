"""
turbopuffer calls for the legal demo: one namespace per firm.

Native embedding: the schema tells turbopuffer to embed "content" on write,
and queries pass ("Embed", text), so there's no embedding service to run.
"""

from __future__ import annotations

import json
import os
import time

from . import contracts

REGION = os.getenv("TURBOPUFFER_REGION", "aws-us-east-1")
PREFIX = os.getenv("NAMESPACE_PREFIX", "legal-search-st")
EMBED_MODEL = os.getenv("EMBED_MODEL", "nvidia/nemotron-3-embed-8b")
EMBED_DIMS = int(os.getenv("EMBED_DIMS", "1024"))

SCHEMA = {
    "content": {
        "type": "string",
        "full_text_search": True,
        "embed": {"model": EMBED_MODEL, "dims": EMBED_DIMS},
    }
}
ATTRS = ["content", "clause", "title", "contract_type", "counterparty", "governing_law",
         "signed_year", "matter", "value_usd"]


def client(api_key: str):
    import turbopuffer

    base_url = os.getenv("TURBOPUFFER_BASE_URL")  # only for local testing against a fake server
    if base_url:
        return turbopuffer.Turbopuffer(api_key=api_key, base_url=base_url)
    return turbopuffer.Turbopuffer(api_key=api_key, region=REGION)


def is_auth_error(e: Exception) -> bool:
    return getattr(e, "status_code", None) == 401


def namespace_for(slug: str) -> str:
    return f"{PREFIX}-{slug}"


def live_namespaces(tpuf) -> list[str]:
    return sorted(n.id for n in tpuf.namespaces(prefix=f"{PREFIX}-"))


def seed(tpuf, slug: str) -> int:
    rows = contracts.generate(slug)
    tpuf.namespace(namespace_for(slug)).write(upsert_rows=rows, distance_metric="cosine_distance", schema=SCHEMA)
    return len(rows)


def delete(tpuf, namespace: str) -> None:
    tpuf.namespace(namespace).delete_all()


def build_filters(contract_type: str | None, law: str | None, min_year: int | None):
    clauses = []
    if contract_type:
        clauses.append(("contract_type", "Eq", contract_type))
    if law:
        clauses.append(("governing_law", "Eq", law))
    if min_year:
        clauses.append(("signed_year", "Gte", int(min_year)))
    if not clauses:
        return None
    return clauses[0] if len(clauses) == 1 else ("And", tuple(clauses))


def search(tpuf, slug: str, q: str, mode: str, filters, top_k: int = 8) -> dict:
    ns = tpuf.namespace(namespace_for(slug))
    base = {"include_attributes": ATTRS}
    if filters:
        base["filters"] = filters
    by_meaning = ("content", "ANN", ("Embed", q))
    by_keyword = ("content", "BM25", q)
    t0 = time.time()
    if mode == "Vector":
        res = ns.query(rank_by=by_meaning, top_k=top_k, **base)
        rows = res.rows
    elif mode == "BM25":
        res = ns.query(rank_by=by_keyword, top_k=top_k, **base)
        rows = res.rows
    else:
        sub = dict(base, top_k=top_k * 3)
        res = ns.multi_query(queries=[dict(sub, rank_by=by_meaning), dict(sub, rank_by=by_keyword)],
                             rerank_by=("RRF",))
        rows = res.results[0].rows[:top_k]
    ms = round((time.time() - t0) * 1000)
    perf = getattr(res, "performance", None)
    perf = perf.to_dict() if hasattr(perf, "to_dict") else (perf or {})
    out = []
    for r in rows:
        d = r.to_dict() if hasattr(r, "to_dict") else dict(r)
        out.append(d)
    return {"rows": out, "ms": ms, "server_ms": perf.get("server_total_ms"),
            "cache": perf.get("cache_temperature"), "code": code_for(slug, q, mode, filters, top_k)}


def code_for(slug: str, q: str, mode: str, filters, top_k: int) -> str:
    """The SDK call, shown in the UI so the demo isn't a black box."""
    q_ = json.dumps(q)
    f = f",\n    filters={filters!r}" if filters else ""
    ns = f'ns = tpuf.namespace("{namespace_for(slug)}")\n'
    if mode == "Vector":
        return ns + f'ns.query(\n    rank_by=("content", "ANN", ("Embed", {q_})),\n    top_k={top_k}{f},\n)'
    if mode == "BM25":
        return ns + f'ns.query(\n    rank_by=("content", "BM25", {q_}),\n    top_k={top_k}{f},\n)'
    return ns + (f'ns.multi_query(\n    queries=[\n'
                 f'        {{"rank_by": ("content", "ANN", ("Embed", {q_})), "top_k": {top_k * 3}{", ..." if filters else ""}}},\n'
                 f'        {{"rank_by": ("content", "BM25", {q_}), "top_k": {top_k * 3}{", ..." if filters else ""}}},\n'
                 f'    ],\n    rerank_by=("RRF",),\n)' + (f"\n# both subqueries use filters={filters!r}" if filters else ""))
