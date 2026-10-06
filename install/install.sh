#!/usr/bin/env bash
# Arc Skills - ephemeral installer bootstrap.
#
#   curl -fsSL https://skills.0xarchit.is-a.dev/install.sh | bash
#
# Fetches the registry, lets you pick skills, downloads the matching ZIPs from
# the latest GitHub Release, verifies SHA-256, and unpacks them into
# ./Agents/skills/<id>/. Nothing is installed globally. Nothing persists except
# the skills you pick.
#
# Env: ARC_SKILLS_DIR       target directory (default ./Agents/skills)
#      ARC_SKILLS_REPO      owner/repo (default 0xArchit/arc-skills)
#      ARC_SKILLS_API / ARC_SKILLS_DL  release API + download base overrides
#      ARC_SKILLS_FORCE=1   overwrite without asking
#      ARC_SKILLS_SKILLS    "react,nextjs" - skip the menu (unattended)
#      ARC_SKILLS_LIB=1     source only, do not run (used by tests)

set -euo pipefail

REPO="${ARC_SKILLS_REPO:-0xArchit/arc-skills}"
API_URL="${ARC_SKILLS_API:-https://api.github.com/repos/$REPO/releases/latest}"
DL_BASE="${ARC_SKILLS_DL:-https://github.com/$REPO/releases/download}"

DEST="${ARC_SKILLS_DIR:-$PWD/Agents/skills}"
FORCE="${ARC_SKILLS_FORCE:-}"
TMP=""

# ── output ──────────────────────────────────────────────────────────────────
die() { printf '\n  \033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }
ok()  { printf '  \033[32m✓\033[0m %s\n' "$*"; }
dim() { printf '  \033[90m%s\033[0m\n' "$*"; }

cleanup() { if [ -n "$TMP" ]; then rm -rf -- "$TMP"; fi; return 0; }

# ── http ────────────────────────────────────────────────────────────────────
if command -v curl >/dev/null 2>&1; then
  GET()   { curl -fsSL --connect-timeout 15 "$1"; }
  FETCH() { curl -fL --progress-bar --connect-timeout 15 -o "$2" "$1"; }
elif command -v wget >/dev/null 2>&1; then
  GET()   { wget -qO- --timeout=15 "$1"; }
  FETCH() { wget -q --show-progress -O "$2" "$1"; }
else
  die "curl or wget is required."
fi

# ── registry parsing ────────────────────────────────────────────────────────
# registry.json -> TSV: id \t name \t category \t tags \t description
# Hand-rolled so the installer needs no jq. Assumes the documented shape.
parse_registry() {
  awk '
    { L = length($0)
      for (i = 1; i <= L; i++) {
        c = substr($0, i, 1)
        if (!ins) { if (c == "[") ins = 1; continue }
        if (depth == 0 && c != "{") continue
        buf = buf c
        if (c == "{") depth++
        else if (c == "}") { depth--; if (depth == 0) { print buf; buf = "" } }
      }
    }
  ' | while IFS= read -r obj; do
    id=$(printf '%s' "$obj" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    [ -n "$id" ] || continue
    name=$(printf '%s' "$obj" | sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    cat=$(printf '%s' "$obj"  | sed -n 's/.*"category"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    tags=$(printf '%s' "$obj" | sed -n 's/.*"tags"[[:space:]]*:[[:space:]]*\[\([^]]*\)\].*/\1/p' | tr -d '"' | tr ',' ' ' | tr -s ' ' | sed 's/^ *//;s/ *$//')
    desc=$(printf '%s' "$obj" | sed -n 's/.*"description"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$name" "$cat" "$tags" "$desc"
  done
}

# Pull one field out of a flat JSON blob: json_field "$manifest" react sha256
json_field() { # $1=json  $2=skill id  $3=field
  printf '%s' "$1" | tr -d '\n' \
    | grep -o "\"$2\"[^}]*\"$3\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
    | head -1 | sed 's/.*"\([^"]*\)"$/\1/'
}

# ── archive safety ──────────────────────────────────────────────────────────
# Rejects absolute paths, drive letters and any `..` segment. Reads entry names
# on stdin; prints the offending lines and returns 1 if anything looks unsafe.
assert_safe_entries() {
  local bad
  bad=$(grep -nE '(^/|^[A-Za-z]:[\\/]|(^|/)\.\.(/|$)|(^|\\)\.\.(\\|$))' || true)
  if [ -n "$bad" ]; then
    printf '%s\n' "$bad" >&2
    return 1
  fi
}

list_entries() { # $1 = zip path
  if command -v unzip >/dev/null 2>&1; then unzip -Z1 -- "$1"
  elif command -v tar >/dev/null 2>&1; then tar -tf "$1"
  else die "unzip (or tar) is required to extract files."
  fi
}

extract_zip() { # $1 = zip  $2 = destination dir
  if command -v unzip >/dev/null 2>&1; then unzip -q -- "$1" -d "$2"
  else tar -xf "$1" -C "$2"
  fi
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
  elif command -v openssl >/dev/null 2>&1; then openssl dgst -sha256 "$1" | awk '{print $NF}'
  else die "No SHA-256 tool found (sha256sum / shasum / openssl)."
  fi
}

# ── terminal ────────────────────────────────────────────────────────────────
# `curl | bash` feeds the script in on stdin, so keys must come from the tty.
if [ -t 1 ] && [ -r /dev/tty ]; then TTY=/dev/tty; else TTY=""; fi

# Blocks for one keypress. Prints UP / DOWN / ENTER / TOGGLE / QUIT / <char>.
read_key() {
  local k rest
  IFS= read -rsn1 k < "$TTY" || { echo QUIT; return; }
  case "$k" in
    $'\e')
      IFS= read -rsn2 -t 1 rest < "$TTY" || rest=""
      case "$rest" in
        '[A') echo UP ;;
        '[B') echo DOWN ;;
        '')   echo QUIT ;;
        *)    echo OTHER ;;
      esac ;;
    $'\r'|$'\n'|'') echo ENTER ;;
    ' ') echo TOGGLE ;;
    *)   echo "$k" ;;
  esac
}

matches() { # $1 = skill index, $2 = lowercase needle
  printf '%s %s %s %s %s' "${IDS[$1]}" "${NAMES[$1]}" "${CATS[$1]}" "${TAGS[$1]}" "${DESCS[$1]}" \
    | tr '[:upper:]' '[:lower:]' | grep -qF -- "$2"
}

apply_filter() {
  local i
  VIEW=()
  for ((i = 0; i < ${#IDS[@]}; i++)); do
    if [ -z "$FILTER" ] || matches "$i" "$FILTER"; then VIEW+=("$i"); fi
  done
  [ "$CUR" -ge "${#VIEW[@]}" ] && CUR=0
  return 0
}

draw() {
  printf '\033[2J\033[H'
  printf '\n  \033[36mARC SKILLS\033[0m\n\n'
  dim "Available skills (${#IDS[@]})"
  dim "──────────────────────────────────────"
  printf '\n'
  local i idx mark
  for ((i = 0; i < ${#VIEW[@]}; i++)); do
    idx=${VIEW[$i]}
    if [ "${SEL[$idx]:-0}" = 1 ]; then mark='x'; else mark=' '; fi
    if [ "$i" -eq "$CUR" ]; then
      printf '  \033[36m>\033[0m [%s] \033[1m%-22s\033[0m \033[90m%s\033[0m\n' "$mark" "${NAMES[$idx]}" "${CATS[$idx]}"
    else
      printf '    [%s] %-22s \033[90m%s\033[0m\n' "$mark" "${NAMES[$idx]}" "${CATS[$idx]}"
    fi
  done
  [ "${#VIEW[@]}" -eq 0 ] && printf '    (no matches)\n'
  printf '\n'
  dim "↑↓ move   space select   a all   / search   enter install   q quit"
  if [ -n "$FILTER" ]; then printf '  \033[90mfilter: %s\033[0m\n' "$FILTER"; fi
}

# Sets the global PICKS array to the chosen skill ids.
menu() {
  local i
  SEL=(); for ((i = 0; i < ${#IDS[@]}; i++)); do SEL+=(0); done
  CUR=0; FILTER=""; VIEW=(); PICKS=(); apply_filter

  while :; do
    draw
    case "$(read_key)" in
      UP)   [ "${#VIEW[@]}" -gt 0 ] && CUR=$(( CUR > 0 ? CUR - 1 : ${#VIEW[@]} - 1 )) ;;
      DOWN) [ "${#VIEW[@]}" -gt 0 ] && CUR=$(( CUR < ${#VIEW[@]} - 1 ? CUR + 1 : 0 )) ;;
      TOGGLE) if [ "${#VIEW[@]}" -gt 0 ]; then i=${VIEW[$CUR]}; SEL[$i]=$(( 1 - ${SEL[$i]:-0} )); fi ;;
      a|A)  for i in "${VIEW[@]}"; do SEL[$i]=1; done ;;
      /)    printf '\n  Search: '; IFS= read -r FILTER < "$TTY" || FILTER=""
            FILTER=$(printf '%s' "$FILTER" | tr '[:upper:]' '[:lower:]'); apply_filter ;;
      ENTER) [ "${#VIEW[@]}" -gt 0 ] || continue
             PICKS=()
             for i in "${!IDS[@]}"; do [ "${SEL[$i]:-0}" = 1 ] && PICKS+=("${IDS[$i]}"); done
             # Nothing ticked? Take the highlighted one - single-select convenience.
             [ "${#PICKS[@]}" -gt 0 ] || PICKS=("${IDS[${VIEW[$CUR]}]}")
             return 0 ;;
      q|Q|QUIT) printf '\n'; exit 0 ;;
    esac
  done
}

# ── install ─────────────────────────────────────────────────────────────────
install_one() { # $1 = skill id
  local id="$1" dest="$DEST/$1" asset sha expected zip name idx a=""
  for idx in "${!IDS[@]}"; do [ "${IDS[$idx]}" = "$id" ] && name="${NAMES[$idx]}"; done
  name="${name:-$id}"

  printf '\n  \033[1m%s\033[0m\n' "$name"

  if [ -e "$dest" ]; then
    if [ "$FORCE" = "1" ]; then
      ok "replacing existing install (ARC_SKILLS_FORCE=1)"
    else
      printf '  %s is already installed. Overwrite? [y/N] ' "$name"
      IFS= read -r a < "${TTY:-/dev/null}" || a=""
      case "$a" in [yY]*) ;; *) printf '  skipped\n'; return 0 ;; esac
    fi
    rm -rf -- "$dest"
  fi

  asset=$(json_field "$MANIFEST" "$id" "asset"); [ -n "$asset" ] || asset="$id.zip"
  expected=$(json_field "$MANIFEST" "$id" "sha256")
  [ -n "$expected" ] || die "$name is not part of release $TAG. Nothing was installed."

  zip="$TMP/$asset"
  printf '  Downloading...\n'
  FETCH "$DL_BASE/$TAG/$asset" "$zip" || die "Download failed for $asset."

  printf '  Verifying...\n'
  sha=$(sha256_of "$zip")
  if [ "$sha" != "$expected" ]; then
    rm -f -- "$zip"
    printf '  \033[31m✗ Checksum verification failed.\033[0m\n' >&2
    printf '    expected %s\n    got      %s\n    Nothing was installed.\n' "$expected" "$sha" >&2
    return 1
  fi
  ok "SHA-256 verified"

  printf '  Extracting...\n'
  if ! list_entries "$zip" | assert_safe_entries; then
    rm -f -- "$zip"
    die "Unsafe paths in $asset - refusing to extract. Nothing was installed."
  fi
  mkdir -p "$TMP/x"
  extract_zip "$zip" "$TMP/x" || die "Could not extract $asset (invalid ZIP?)."
  [ -f "$TMP/x/SKILL.md" ] || die "$asset contains no SKILL.md - not a skill bundle."

  mkdir -p -- "$DEST"
  rm -rf -- "$dest"
  mv -- "$TMP/x" "$dest"
  mkdir -p "$TMP/x"
  ok "installed"
}

main() {
  printf '\n  \033[36mARC SKILLS\033[0m\n\n'
  printf '  Checking releases... '

  TAG=$(GET "$API_URL" 2>/dev/null | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1) || true
  [ -n "${TAG:-}" ] || die "Could not find a release for $REPO.
  Check your internet connection and try again."
  printf '\r  \033[32m✓\033[0m %s\n' "$TAG"

  printf '  Fetching skills... '

  local reg
  reg=$(GET "$DL_BASE/$TAG/registry.json" 2>/dev/null) \
    || die "Could not fetch the skill registry.
  Check your internet connection and try again."

  IDS=(); NAMES=(); CATS=(); TAGS=(); DESCS=()
  while IFS=$'\t' read -r id name cat tags desc; do
    IDS+=("$id"); NAMES+=("$name"); CATS+=("$cat"); TAGS+=("$tags"); DESCS+=("$desc")
  done < <(printf '%s' "$reg" | parse_registry)

  [ "${#IDS[@]}" -gt 0 ] || die "The registry lists no skills (invalid registry?)."
  printf '\r  \033[32m✓\033[0m %s skills available\n' "${#IDS[@]}"

  local -a picks=()
  if [ -n "${ARC_SKILLS_SKILLS:-}" ]; then
    IFS=',' read -ra picks <<< "${ARC_SKILLS_SKILLS}"
  else
    [ -n "$TTY" ] || die "No interactive terminal available.
  Set ARC_SKILLS_SKILLS=react,nextjs for unattended use."
    menu
    picks=("${PICKS[@]}")
  fi

  local id i known
  for id in "${picks[@]}"; do
    id=$(printf '%s' "$id" | tr -d ' ')
    known=0
    for i in "${!IDS[@]}"; do [ "${IDS[$i]}" = "$id" ] && known=1; done
    [ "$known" = 1 ] || die "Unknown skill: $id"
  done

  printf '\n'
  for id in "${picks[@]}"; do
    for i in "${!IDS[@]}"; do
      [ "${IDS[$i]}" = "$id" ] && printf '  %s\n    %s\n' "${NAMES[$i]}" "${DESCS[$i]}"
    done
  done

  if [ "${#picks[@]}" -gt 1 ]; then
    printf '\n  Install %d skills? [Y/n] ' "${#picks[@]}"
    local a=""; IFS= read -r a < "${TTY:-/dev/null}" || a=""
    case "$a" in [nN]*) printf '\n'; exit 0 ;; esac
  fi


  MANIFEST=$(GET "$DL_BASE/$TAG/manifest.json" 2>/dev/null) || true
  [ -n "${MANIFEST:-}" ] || die "Release $TAG has no manifest.json - cannot verify downloads."

  TMP=$(mktemp -d "${TMPDIR:-/tmp}/arc-skills.XXXXXX") || die "Could not create a temporary directory."
  trap cleanup EXIT INT TERM

  local -a installed=() failed=()
  for id in "${picks[@]}"; do
    if install_one "$id"; then installed+=("$id"); else failed+=("$id"); fi
  done

  printf '\n'
  if [ "${#installed[@]}" -gt 0 ]; then
    printf '  Installed:\n\n'
    for id in "${installed[@]}"; do ok "$id"; done
    printf '\n  Location:\n  %s/\n' "$DEST"
  fi
  if [ "${#failed[@]}" -gt 0 ]; then
    printf '\n  \033[31mFailed:\033[0m\n'
    for id in "${failed[@]}"; do printf '  ✗ %s\n' "$id"; done
    printf '\n'
    exit 1
  fi
  printf '\n'
}

if [ -z "${ARC_SKILLS_LIB:-}" ]; then main "$@"; fi
