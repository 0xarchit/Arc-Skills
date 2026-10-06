#!/usr/bin/env bash
# Build registry.json from the YAML frontmatter of skills/*/SKILL.md.
#
# The frontmatter is the single source of truth - CI runs this on every push, so
# registry.json is generated, never hand-edited.
#
#   bash scripts/build-registry.sh                 # write registry.json
#   bash scripts/build-registry.sh --check         # exit 1 if it is out of date
#   REGISTRY_OUT=/tmp/out.json bash scripts/build-registry.sh ./fixture
#
# Required frontmatter: id, name, description, category, tags
#   id: react
#   name: React
#   description: One line, shown in the installer menu.
#   category: frontend
#   tags: [react, javascript, frontend]

set -euo pipefail
cd "$(dirname "$0")/.."

CHECK=0
DIR=""
for arg in "$@"; do
  case "$arg" in
    --check) CHECK=1 ;;
    *) DIR="$arg" ;;
  esac
done
SKILLS_DIR="${DIR:-skills}"
OUT="${REGISTRY_OUT:-registry.json}"

fail() { printf 'build-registry: %s\n' "$*" >&2; exit 1; }

# Read one key from the frontmatter block (between the first pair of --- lines).
fm() { # $1 = file, $2 = key
  awk -v key="$2" '
    NR == 1 && $0 !~ /^---[[:space:]]*$/ { exit }
    /^---[[:space:]]*$/ { if (seen) exit; seen = 1; next }
    seen {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      if (index(line, key ":") == 1) {
        v = substr(line, length(key) + 2)
        sub(/^[[:space:]]+/, "", v)
        sub(/[[:space:]]+$/, "", v)
        print v
        exit
      }
    }
  ' "$1"
}

jstr() { # escape a string for JSON
  local s="$1" bs q
  bs=$(printf '\')   # backslash, cited in octal so this line needs no escapes
  q=$(printf '"')    # double quote
  s="${s//"$bs"/"$bs$bs"}"
  s="${s//"$q"/"$bs$q"}"
  printf '%s' "$s"
}

tags_json() { # "[a, b]" -> "\"a\", \"b\""
  local IFS=',' item out=""
  local t="${1#[}"; t="${t%]}"
  for item in $t; do
    item="$(printf '%s' "$item" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -n "$item" ] || continue
    out="$out${out:+, }\"$(jstr "$item")\""
  done
  printf '%s' "$out"
}

build() {
  local first=1 dir file id name description category tags
  printf '{\n  "version": 1,\n  "skills": [\n'
  for dir in "$SKILLS_DIR"/*/; do
    file="$dir/SKILL.md"
    [ -f "$file" ] || continue

    id="$(fm "$file" id)"
    name="$(fm "$file" name)"
    description="$(fm "$file" description)"
    category="$(fm "$file" category)"
    tags="$(fm "$file" tags)"

    [ -n "$id" ]          || fail "$file: missing 'id' in frontmatter"
    [ "$id" = "$(basename "$dir")" ] || \
      fail "$file: id '$id' does not match its directory '$(basename "$dir")'"
    case "$id" in
      *[!a-z0-9-]*) fail "$file: id '$id' must be a lowercase slug (a-z, 0-9, hyphen)" ;;
    esac
    [ -n "$name" ]        || fail "$file: missing 'name' in frontmatter"
    [ -n "$description" ] || fail "$file: missing 'description' in frontmatter"
    [ -n "$category" ]    || fail "$file: missing 'category' in frontmatter"

    [ "$first" = 1 ] || printf ',\n'
    first=0
    printf '    {\n'
    printf '      "id": "%s",\n'          "$(jstr "$id")"
    printf '      "name": "%s",\n'        "$(jstr "$name")"
    printf '      "description": "%s",\n' "$(jstr "$description")"
    printf '      "category": "%s",\n'    "$(jstr "$category")"
    printf '      "tags": [%s]\n'         "$(tags_json "$tags")"
    printf '    }'
  done
  printf '\n  ]\n}\n'
}

if [ "$CHECK" = 1 ]; then
  tmp="$(mktemp "${TMPDIR:-/tmp}/registry.XXXXXX")"
  build > "$tmp"
  if [ ! -f "$OUT" ]; then
    printf '%s does not exist - run scripts/build-registry.sh
' "$OUT" >&2
    rm -f "$tmp"
    exit 1
  elif diff -q "$OUT" "$tmp" >/dev/null 2>&1; then
    printf 'registry.json is up to date\n'
    rm -f "$tmp"
  else
    printf 'registry.json is stale - run scripts/build-registry.sh\n' >&2
    diff -u "$OUT" "$tmp" >&2 || true
    rm -f "$tmp"
    exit 1
  fi
else
  tmp="$(mktemp "${TMPDIR:-/tmp}/registry.XXXXXX")" || fail "could not create a temp file"
  trap 'rm -f "$tmp"' EXIT
  build > "$tmp"
  mv -f "$tmp" "$OUT"
  trap - EXIT
  printf 'wrote %s (%s skills)\n' "$OUT" "$(grep -c '"id":' "$OUT")" >&2
fi
