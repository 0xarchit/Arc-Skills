#!/usr/bin/env bash
# Self-check for install.sh internals. No network, nothing written outside a temp
# directory. Run it after touching install.sh:
#
#   bash tests/selftest.sh

set -euo pipefail
cd "$(dirname "$0")/.."
ARC_SKILLS_LIB=1 . ./install/install.sh

pass=0; fail=0
ok_t() { pass=$((pass + 1)); printf '  ✓ %s\n' "$1"; }
no_t() { fail=$((fail + 1)); printf '  ✗ %s\n     expected: %s\n     actual:   %s\n' "$1" "$2" "$3"; }
eq()   { if [ "$2" = "$3" ]; then ok_t "$1"; else no_t "$1" "$2" "$3"; fi; }

check_n() { if [ "$2" = "$3" ]; then ok_t "$1"; else no_t "$1" "$2" "$3"; fi; }

must_accept() { # $1 label, stdin data
  if printf '%s\n' "$2" | assert_safe_entries >/dev/null 2>&1; then ok_t "accepts $1"
  else no_t "accepts $1" "accepted" "rejected"; fi
}
must_reject() {
  if printf '%s\n' "$2" | assert_safe_entries >/dev/null 2>&1; then no_t "rejects $1" "rejected" "accepted"
  else ok_t "rejects $1"; fi
}

printf '\nregistry parsing\n'

REG=$(cat <<'JSON'
{
  "version": 1,
  "skills": [
    {
      "id": "react",
      "name": "React",
      "description": "React dev.",
      "category": "frontend",
      "tags": ["react", "js"]
    },
    {
      "id": "java",
      "name": "Java",
      "description": "Java dev.",
      "category": "backend",
      "tags": []
    }
  ]
}
JSON
)

rows=()
while IFS= read -r line; do rows+=("$line"); done < <(printf '%s' "$REG" | parse_registry)
eq "two skills parsed" "2" "${#rows[@]}"
eq "row 1 fields" "$(printf 'react\tReact\tfrontend\treact js\tReact dev.')" "${rows[0]:-}"
eq "row 2 survives empty tags" "$(printf 'java\tJava\tbackend\t\tJava dev.')" "${rows[1]:-}"

printf '\nmanifest lookup\n'

MAN='{"version":1,"release":"v1.0.7","skills":{"react":{"asset":"react.zip","sha256":"aa11"},"react-native":{"asset":"rn.zip","sha256":"bb22"}}}'
eq "sha256 for react"      "aa11"    "$(json_field "$MAN" react sha256)"
eq "sha256 for react-native" "bb22"  "$(json_field "$MAN" react-native sha256)"
eq "asset for react-native"  "rn.zip" "$(json_field "$MAN" react-native asset)"
eq "missing skill yields nothing" "" "$(json_field "$MAN" nosuch sha256)"

printf '\nzip path traversal\n'

must_accept "plain file"            "SKILL.md"
must_accept "nested file"           "references/checklist.md"
must_accept "dotted filename"       "assets/logo.v2.png"
must_accept "parent-ish name"       "skills/react-2/SKILL.md"
must_reject "relative escape"       "../evil.sh"
must_reject "nested escape"         "a/../../evil.sh"
must_reject "trailing escape"       "a/.."
must_reject "absolute path"         "/etc/passwd"
must_reject "windows absolute"      'C:\Windows\System32\evil.dll'
must_reject "windows escape"        '..\evil.exe'
must_reject "windows nested escape" 'a\..\..\evil.exe'

printf '\nchecksums\n'

tmp=$(mktemp -d "${TMPDIR:-/tmp}/arc-skills-test.XXXXXX")
printf 'abc' > "$tmp/a"
eq "sha256 of 'abc'" \
   "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" \
   "$(sha256_of "$tmp/a")"
printf 'abd' > "$tmp/b"
if [ "$(sha256_of "$tmp/a")" = "$(sha256_of "$tmp/b")" ]; then
  no_t "different content hashes differently" "different" "identical"
else ok_t "different content hashes differently"; fi
rm -f "$tmp/a" "$tmp/b"; rmdir "$tmp"

printf '
menu
'

if true; then
  IDS=(react java docker); NAMES=(React Java Docker)
  CATS=(frontend backend devops); TAGS=("react ui" "java jvm" "docker containers")
  DESCS=("React dev." "Java dev." "Docker dev.")

  # A pipe stands in for the tty. (A fifo would deadlock: reopening one for
  # reading blocks once the writer has closed, even with bytes still buffered.)
  drive_menu() { # $1 = keys to feed; the result lands in PICKS
    TTY=/dev/stdin
    menu < <(printf '%b' "$1")
    TTY=""
    return 0
  }

  drive_menu '[B 
'                 # down, space, enter
  eq "arrow + space selects the second skill" "java" "${PICKS[0]:-}"
  check_n "only the ticked skill is returned" "1" "${#PICKS[@]}"

  drive_menu '/ja

'                   # search, then enter on the single match
  eq "search narrows to a match" "java" "${PICKS[0]:-}"

  drive_menu 'a
'                        # select all
  check_n "select-all returns every skill" "3" "${#PICKS[@]}"
else
  printf '  (menu tests skipped)
'
fi

printf '
registry build
'

RSK=$(mktemp -d "${TMPDIR:-/tmp}/arcskills-reg.XXXXXX")
mkdir -p "$RSK/skills/alpha" "$RSK/skills/beta" "$RSK/bad/gamma" "$RSK/bad2/epsilon"

printf '%s
' '---' 'id: alpha' 'name: Alpha' "description: Says \"hi\" to everyone."   'category: demo' 'tags: [one, two]' '---' '# Alpha' > "$RSK/skills/alpha/SKILL.md"
printf '%s
' '---' 'id: beta' 'name: Beta' 'description: Second.'   'category: demo' 'tags: []' '---' '# Beta' > "$RSK/skills/beta/SKILL.md"
printf '%s
' '---' 'id: delta' 'name: Delta' 'description: Mismatch.'   'category: demo' '---' '# Delta' > "$RSK/bad/gamma/SKILL.md"
printf '%s
' '---' 'id: epsilon' 'name: Epsilon' '---' '# Epsilon'   > "$RSK/bad2/epsilon/SKILL.md"

REGISTRY_OUT="$RSK/out.json" bash scripts/build-registry.sh "$RSK/skills" >/dev/null 2>&1
check_n "one entry per skill" "2" "$(grep -c '"id"' "$RSK/out.json")"
grep -qF '"tags": ["one", "two"]' "$RSK/out.json"   && ok_t "inline tag list parsed" || no_t "inline tag list parsed" "tags missing"
grep -qF 'Says \"hi\" to everyone.' "$RSK/out.json"   && ok_t "double quotes escaped" || no_t "double quotes escaped" "not escaped"
if command -v python >/dev/null 2>&1; then
  python -I -c "import json,sys; json.load(open(sys.argv[1]))" "$RSK/out.json" 2>/dev/null     && ok_t "output parses as JSON" || no_t "output parses as JSON" "unparseable"
fi
REGISTRY_OUT="$RSK/x.json" bash scripts/build-registry.sh "$RSK/bad" >/dev/null 2>&1   && no_t "id not matching its directory is rejected" "exit 0" "exit 1"   || ok_t "id not matching its directory is rejected"
REGISTRY_OUT="$RSK/x.json" bash scripts/build-registry.sh "$RSK/bad2" >/dev/null 2>&1   && no_t "missing required key is rejected" "exit 0" "exit 1"   || ok_t "missing required key is rejected"

find "$RSK" -depth -delete 2>/dev/null

printf '\nPowerShell source\n'

# Windows PowerShell decodes a BOM-less .ps1 as ANSI. One stray non-ASCII byte
# (a literal U+FEFF in a regex, say) turns into three junk characters there and
# the script breaks only on 5.1 - which is exactly how it broke once already.
nonascii=$(LC_ALL=C tr -d '\000-\177' < install/install.ps1 | wc -c | tr -d ' ')
check_n "install.ps1 is pure ASCII" "0" "$nonascii"

printf '\n%s passed, %s failed\n\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
