#!/usr/bin/env bash
# Offline end-to-end test for install.sh against a fake release tree served over
# file:// URLs. No network, no GitHub account.
#
#   bash tests/e2e.sh
#
# Covers: registry fetch, release discovery, asset selection, checksum
# verification, extraction, install location, existing-directory handling,
# path-traversal rejection, ARC_SKILLS_DIR override and temp cleanup.

set -euo pipefail
cd "$(dirname "$0")/.."
INSTALLER="$PWD/install/install.sh"

pass=0; fail=0
ok_t() { pass=$((pass + 1)); printf '  ✓ %s\n' "$1"; }
no_t() { fail=$((fail + 1)); printf '  ✗ %s\n     %s\n' "$1" "$2"; }
check() { if [ "$2" = "$3" ]; then ok_t "$1"; else no_t "$1" "expected [$2] got [$3]"; fi; }
has()   { if [ -e "$1" ]; then ok_t "$2"; else no_t "$2" "missing: $1"; fi; }
hasnt() { if [ -e "$1" ]; then no_t "$2" "should not exist: $1"; else ok_t "$2"; fi; }

ESC=$(printf '')
plain() { sed "s/${ESC}\[[0-9;]*m//g"; }   # strip ANSI colour before matching

FIX=$(mktemp -d "${TMPDIR:-/tmp}/arcfix.XXXXXX")
PROJ=$(mktemp -d "${TMPDIR:-/tmp}/arcproj.XXXXXX")
TMPROOT="${TMPDIR:-/tmp}"
# snapshot the shared temp root: other things live there, so only assert that
# this run adds nothing (an earlier count-first version failed on stale dirs)
TMP_BEFORE=$(find "$TMPROOT" -maxdepth 1 -name 'arc-skills.*' 2>/dev/null | wc -l | tr -d ' ')
w() { cygpath -m "$1" 2>/dev/null || printf '%s' "$1"; }   # windows path for file:// URLs
FIXURL="file:///$(w "$FIX")"

cleanup() { find "$FIX" -depth -delete 2>/dev/null; find "$PROJ" -depth -delete 2>/dev/null; return 0; }
trap cleanup EXIT

# ── fixture ─────────────────────────────────────────────────────────────────
mkdir -p "$FIX/dl/v9.9.9" "$FIX/src/react/references" "$FIX/src/react/examples"

cat > "$FIX/src/react/SKILL.md" <<'MD'
---
id: react
name: React
description: Fixture skill.
---
# React fixture
MD
printf 'nested file
' > "$FIX/src/react/references/checklist.md"
printf 'export const C = 1;
' > "$FIX/src/react/examples/Counter.tsx"

cat > "$FIX/dl/v9.9.9/registry.json" <<'JSON'
{
  "version": 1,
  "skills": [
    { "id": "react",  "name": "React",  "description": "Fixture react.",  "category": "frontend", "tags": ["react", "ui"] },
    { "id": "docker", "name": "Docker", "description": "Fixture docker.", "category": "devops",   "tags": ["docker"] },
    { "id": "java",   "name": "Java",   "description": "Fixture java.",   "category": "backend",  "tags": ["java"] }
  ]
}
JSON

printf '{"tag_name":"v9.9.9"}\n' > "$FIX/latest.json"
printf '{"tag_name":"v0.0.0"}' > "$FIX/badtag.json"   # a tag whose assets do not exist

# zip a directory with entries at the archive root
cat > "$FIX/zipdir.py" <<'PY'
import os, sys, zipfile
src, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for root, _dirs, files in os.walk(src):
        for f in files:
            p = os.path.join(root, f)
            z.write(p, os.path.relpath(p, src).replace(os.sep, "/"))
PY

# a malicious archive: entry escapes the install directory
cat > "$FIX/zipbad.py" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w") as z:
    z.writestr("../evil.txt", "pwned")
    z.writestr("SKILL.md", "# looks legit")
PY

python -I "$FIX/zipdir.py" "$FIX/src/react" "$FIX/dl/v9.9.9/react.zip"
python -I "$FIX/zipdir.py" "$FIX/src/react" "$FIX/dl/v9.9.9/docker.zip"
python -I "$FIX/zipbad.py" "$FIX/dl/v9.9.9/java.zip"

sha() { sha256sum "$1" | cut -d' ' -f1; }
cat > "$FIX/dl/v9.9.9/manifest.json" <<JSON
{
  "version": 1,
  "release": "v9.9.9",
  "skills": {
    "react":  { "asset": "react.zip",  "sha256": "$(sha "$FIX/dl/v9.9.9/react.zip")" },
    "docker": { "asset": "docker.zip", "sha256": "$(printf '0%.0s' $(seq 64))" },
    "java":   { "asset": "java.zip",   "sha256": "$(sha "$FIX/dl/v9.9.9/java.zip")" }
  }
}
JSON

run() { # $1 project dir, $2 skills, rest = extra env assignments
  local proj="$1" skills="$2"; shift 2
  ( cd "$proj" && env \
        ARC_SKILLS_API="$FIXURL/latest.json" ARC_SKILLS_DL="$FIXURL/dl" \
        ARC_SKILLS_SKILLS="$skills" "$@" bash "$INSTALLER" 2>&1 || true )
}

printf '\nhappy path\n'
out=$(run "$PROJ" react | plain)
has "$PROJ/Agents/skills/react/SKILL.md"      "SKILL.md installed"
has "$PROJ/Agents/skills/react/references/checklist.md" "nested references/ installed"
has "$PROJ/Agents/skills/react/examples/Counter.tsx"    "nested examples/ installed"
case "$out" in *"✓ SHA-256 verified"*) ok_t "checksum verified message" ;; *) no_t "checksum verified message" "$out" ;; esac
case "$out" in *"Installed:"*) ok_t "summary printed" ;; *) no_t "summary printed" "$out" ;; esac

printf '\ntarget override\n'
out=$(run "$PROJ" react ARC_SKILLS_DIR="$PROJ/custom" | plain)
has "$PROJ/custom/react/SKILL.md" "ARC_SKILLS_DIR honoured"

printf '\nchecksum mismatch\n'
out=$(run "$PROJ" docker | plain)
case "$out" in *"Checksum verification failed"*) ok_t "mismatch detected" ;; *) no_t "mismatch detected" "$out" ;; esac
hasnt "$PROJ/Agents/skills/docker" "nothing installed on mismatch"

printf '\npath traversal\n'
out=$(run "$PROJ" java | plain)
case "$out" in *"Unsafe paths"*) ok_t "traversal rejected" ;; *) no_t "traversal rejected" "$out" ;; esac
hasnt "$PROJ/Agents/skills/java" "nothing installed on traversal"
check "no file escaped the install dir" "0" "$(find "$PROJ" -name 'evil.txt' | wc -l | tr -d ' ')"

printf '\nexisting install\n'
mkdir -p "$PROJ/Agents/skills/react"; printf 'keep me' > "$PROJ/Agents/skills/react/MARKER"
out=$(run "$PROJ" react < /dev/null | plain)
has "$PROJ/Agents/skills/react/MARKER" "declined overwrite leaves directory alone"

out=$(run "$PROJ" react ARC_SKILLS_FORCE=1 | plain)
hasnt "$PROJ/Agents/skills/react/MARKER" "ARC_SKILLS_FORCE=1 replaces it"
has "$PROJ/Agents/skills/react/SKILL.md" "replacement is complete"

printf '\nunknown skill\n'
out=$(run "$PROJ" nope | plain)
case "$out" in *"Unknown skill: nope"*) ok_t "unknown id refused" ;; *) no_t "unknown id refused" "$out" ;; esac

printf '\nbad registry\n'
out=$( { cd "$PROJ" && ARC_SKILLS_API="$FIXURL/badtag.json" ARC_SKILLS_DL="$FIXURL/dl"          ARC_SKILLS_SKILLS=react bash "$INSTALLER" 2>&1 || true; } | plain )
case "$out" in *"Could not fetch the skill registry"*) ok_t "clean registry error" ;; *) no_t "clean registry error" "$out" ;; esac
case "$out" in *"at line"*|*"Traceback"*) no_t "no stack trace" "$out" ;; *) ok_t "no stack trace" ;; esac

printf '\ntemp cleanup\n'
leftovers=$(find "$TMPROOT" -maxdepth 1 -name 'arc-skills.*' 2>/dev/null | wc -l | tr -d ' ')
check "no temp dirs left behind" "$TMP_BEFORE" "$leftovers"

printf '\n%s passed, %s failed\n\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
