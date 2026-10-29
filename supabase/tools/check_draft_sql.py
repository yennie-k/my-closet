"""Offline parse/lint only. No database client, connection or SQL execution.

Uses pglast installed into ignored build/sql_review_tools, not Flutter packages.
The JSON report is reproducible and intentionally distinguishes grammar from
catalog, policy, Storage, and worker verification.
"""
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "build/sql_review_tools"))
import pglast  # noqa: E402
from pglast import ast  # noqa: E402

report = {
    "review_date": "2026-10-27",
    "parser": "pglast/libpg_query",
    "parser_version": pglast.__version__,
    "embedded_postgresql_parser_version": list(pglast.get_postgresql_version()),
    "database_connection_or_execution": False,
    "catalog_resolution_verified": False,
    "rls_or_storage_behavior_verified": False,
    "real_file_hash_verification_worker_tested": False,
    "files": [],
}
trees = {}
for path in sorted((ROOT / "supabase").glob("**/*.sql")):
    sql = path.read_text(encoding="utf-8")
    statements = pglast.parse_sql(sql)
    blocks = pglast.parse_plpgsql(sql)
    trees[path.name] = statements
    without_comments = re.sub(r"--[^\n]*", "", sql)
    assert not re.search(r"\b(insert\s+into|delete\s+from|update)\s+storage\.(objects|buckets)\b", without_comments, re.I), path
    report["files"].append({
        "path": path.relative_to(ROOT).as_posix(),
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "sql_statements_parsed": len(statements),
        "plpgsql_blocks_parsed": len(blocks),
    })

# Inspect generated SQL AST grants, rather than treating grep as validation.
photo_facts = {
    "photo_state", "photo_path", "photo_sha256", "photo_size_bytes", "photo_verified_at",
    "image_mime_type", "image_width", "image_height", "upload_path", "upload_size_bytes",
    "upload_expires_at", "upload_error_code", "retired_photo_path", "retired_cleanup_after",
}
checks = []
service_grants = []
for raw in trees["01_database.draft.sql"]:
    stmt = raw.stmt
    if not isinstance(stmt, ast.GrantStmt) or not stmt.is_grant or stmt.objtype.name != "OBJECT_TABLE":
        continue
    roles = {role.rolename for role in stmt.grantees}
    tables = {obj.relname for obj in stmt.objects}
    assert not roles.intersection({None, "anon"}), "Unexpected PUBLIC/anon table grant"
    for permission in stmt.privileges:
        cols = {col.sval for col in permission.cols or ()}
        if "authenticated" in roles and "garments" in tables:
            if permission.priv_name == "update":
                assert cols and not cols.intersection(photo_facts)
                assert "upload_state" in cols
            if permission.priv_name == "insert":
                assert cols and not cols.intersection(photo_facts - {"image_mime_type", "image_width", "image_height"})
        if "service_role" in roles:
            assert tables == {"garments"}
            assert permission.priv_name in {"select", "update"} and cols
            assert not cols.intersection({"name", "notes", "material", "materials", "category", "local_id"})
            service_grants.append(permission.priv_name)
assert sorted(service_grants) == ["select", "update"]
checks.append("AST: authenticated has no INSERT/UPDATE grant for trusted photo state/facts/reservations")
checks.append("AST: service_role has only explicit garment photo SELECT/UPDATE columns, no preferences/general CRUD grants")

for raw in trees["02_storage_policies.draft.sql"]:
    assert not isinstance(raw.stmt, (ast.GrantStmt, ast.AlterTableStmt, ast.DropStmt)), "Managed Storage grants/schema must not be modified"
checks.append("AST: Storage draft does not change managed grants/ownership/schema or drop policies")

policy_names = set()
for raw in trees["01_database.draft.sql"]:
    stmt = raw.stmt
    if isinstance(stmt, ast.CreatePolicyStmt):
        policy_names.add(stmt.policy_name)
        if stmt.cmd_name == "update":
            assert stmt.qual is not None and stmt.with_check is not None
assert len(policy_names) == 8
checks.append("AST: eight application CRUD policies; both UPDATE policies have USING and WITH CHECK")
report["static_checks"] = checks
target = ROOT / "docs/supabase/sql-review-static-report.json"
target.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps(report, ensure_ascii=False, indent=2))
