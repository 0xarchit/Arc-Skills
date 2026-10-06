# Arc Skills

A one-command, throwaway installer for personal AI-agent skill bundles.

Nothing is installed globally. There is no CLI, no binary, no daemon, no PATH
change and no package manager. You run one command, pick the skills you want,
and the only thing left on disk is the skill directories you chose.

```powershell
# Windows
irm https://skills.0xarchit.is-a.dev/install.ps1 | iex
```

```bash
# Linux / macOS / WSL
curl -fsSL https://skills.0xarchit.is-a.dev/install.sh | bash
# or
wget -qO- https://skills.0xarchit.is-a.dev/install.sh | bash
```

```
  ARC SKILLS

  ✓ v1.0.42
  ✓ 3 skills available

  Available skills (3)
  ──────────────────────────────────────

  > [ ] <skill-name>              <category>
    [ ] <skill-name>              <category>
    [ ] <skill-name>              <category>

  ↑↓ move   space select   a all   / search   enter install   q quit
```

## What it does

```
bootstrap script  →  latest GitHub Release  →  registry.json + manifest.json
                  →  menu  →  download ZIP  →  verify SHA-256  →  extract
                  →  ./Agents/skills/<skill-id>/  →  exit
```

Everything the installer needs - the menu metadata, the checksums and the skill
bundles themselves - is read out of the latest release. The repository holds no
generated files, so there is nothing to keep in sync and no version to hardcode.

Skills land next to **wherever you ran the command** - never in a global
location, never relative to the script:

```
~/projects/my-agent$ curl -fsSL https://skills.0xarchit.is-a.dev/install.sh | bash
...
~/projects/my-agent/Agents/skills/<skill-id>/
```

The installer downloads, verifies and unpacks. It never executes anything from a
skill bundle.

## Options

All optional; the defaults are what you want unless you are scripting.

| Environment variable | Effect |
| --- | --- |
| `ARC_SKILLS_DIR` | Install into this directory instead of `./Agents/skills` |
| `ARC_SKILLS_SKILLS` | Comma-separated ids - skips the menu (`<skill-id>,<skill-id>`) |
| `ARC_SKILLS_FORCE=1` | Overwrite existing skills without asking |
| `ARC_SKILLS_REPO` | `owner/repo` to install from (default `0xArchit/arc-skills`) |
| `ARC_SKILLS_API` / `ARC_SKILLS_DL` | Release API and download base overrides |

```powershell
$env:ARC_SKILLS_DIR = "C:\some\project\Agents\skills"
irm https://skills.0xarchit.is-a.dev/install.ps1 | iex
```

```bash
ARC_SKILLS_DIR=/some/project/Agents/skills \
  curl -fsSL https://skills.0xarchit.is-a.dev/install.sh | bash
```

Select several skills in one session with `space`, then `enter`; they are
processed one after another. If a skill already exists you are asked before
anything is replaced.

## Adding a skill

A skill is a directory whose `SKILL.md` frontmatter is the **single source of
truth** - the registry, the menu and the website are all generated from it.

```markdown
---
id: <skill-id>
name: <Display Name>
description: One line saying when an agent should reach for this skill.
category: <category>
tags: [tag-one, tag-two]
---

# <Display Name>

...the body, shipped as-is...
```

| Key | Required | Notes |
| --- | --- | --- |
| `id` | yes | Lowercase slug, and it must match the directory name. It becomes the install path and the asset name, so a space or a capital here produces a download URL that cannot be fetched. |
| `name` | yes | Display name in the menu and on the site. |
| `description` | yes | One line, shown under the name. |
| `category` | yes | One word, shown beside the name. |
| `tags` | no | Inline list. Also searched by the menu and the site. |

To add a skill:

1. Create `skills/<id>/SKILL.md` with the frontmatter above. Add `references/`,
   `examples/` or `assets/` if you want them shipped alongside.
2. Push to `main`.

CI generates `registry.json` from the frontmatter, packages each skill into its
own ZIP, hashes everything and publishes a release. You never commit a ZIP and
you never hand-edit the registry.

To preview locally:

```bash
bash scripts/build-registry.sh            # writes registry.json (git-ignored)
bash scripts/build-registry.sh --check    # exit 1 if it would change
```

## Repository layout

```
arc-skills/
├── skills/
│   └── <skill-id>/
│       ├── SKILL.md          # frontmatter is the source of truth
│       ├── references/       # optional, shipped as-is
│       ├── examples/         # optional
│       └── assets/           # optional
├── install/
│   ├── install.ps1
│   └── install.sh
├── scripts/
│   └── build-registry.sh     # SKILL.md frontmatter -> registry.json
├── tests/
│   ├── selftest.sh           # unit checks: parser, traversal guard, menu
│   ├── e2e.sh                # full offline install, bash
│   └── e2e.ps1               # full offline install, PowerShell
├── index.html                # landing page, renders registry.json
├── CNAME                     # skills.0xarchit.is-a.dev
└── .github/workflows/
    ├── pages.yml             # assembles and deploys the site
    └── release.yml           # packages skills and publishes a release
```

## Releases

Every push that touches `skills/**` or `scripts/**` produces one release:

```
v1.0.42
├── registry.json      # generated from skill frontmatter - the menu metadata
├── manifest.json      # asset names + SHA-256 for every skill
├── <skill-id>.zip     # one ZIP per skill
└── ...
```

```json
{
  "version": 1,
  "release": "v1.0.42",
  "skills": {
    "<skill-id>": { "asset": "<skill-id>.zip", "sha256": "9f2c..." }
  }
}
```

The installer asks the public Releases API for the latest tag, then reads
`registry.json` and `manifest.json` from that tag and finds each skill ZIP by id.
No version is ever hardcoded, and `manifest.json` is the source of the expected
checksum.

A skill ZIP contains the *contents* of the skill directory, with `SKILL.md` at
the archive root. Any entry with an absolute path, a drive letter or a `..`
segment is rejected before extraction.

## The domain

`skills.0xarchit.is-a.dev` is only a stable place to fetch the two bootstrap
scripts from:

| Path | Serves |
| --- | --- |
| `/` | `index.html` - the landing page |
| `/install.sh` | `install/install.sh` |
| `/install.ps1` | `install/install.ps1` |
| `/registry.json` | generated at deploy time from the skill frontmatter |

GitHub Pages serves those paths. It cannot run a build command, so
`.github/workflows/pages.yml` assembles the site on every push: it copies
`index.html`, `CNAME` and the two bootstrap scripts into `_site/`, then generates
`registry.json` from the skill frontmatter. `CNAME` points Pages at
`skills.0xarchit.is-a.dev`.

The build step exists for the landing page. A browser cannot read `registry.json`
straight from the release, because GitHub serves release assets without
`Access-Control-Allow-Origin`, so a cross-origin `fetch` is blocked. Generating
the file during the deploy puts it on the same origin as the page, with no CORS,
no API rate limit, and still nothing committed.

The installers do **not** depend on the domain: they read everything from the
release, so any host that serves the two scripts as raw text will do.

## Testing

```bash
bash tests/selftest.sh                     # frontmatter parser, traversal guard, checksums, menu
bash tests/e2e.sh                          # full run against a fake release
pwsh -NoProfile -File tests/e2e.ps1        # same for the PowerShell installer
powershell -NoProfile -File tests/e2e.ps1  # ...and on Windows PowerShell 5.1
```

The e2e tests build a throwaway release tree (a valid ZIP, one with a wrong
checksum, one with a `../` entry), serve it locally and drive the real installer
against it. No network or GitHub account needed. `e2e.ps1` needs `python` only
to serve the fixture.

## Deliberately not included

No compiled binary, no global command, no package manager, no version database,
no persistent state, no auto-update, no background service. Bash, PowerShell,
JSON, ZIP and GitHub Releases - the whole thing is two scripts and a workflow.

## Security notes

- Every download is verified against the SHA-256 in `manifest.json` before
  anything is unpacked; a mismatch aborts and deletes the file.
- Archive entries are checked before extraction: absolute paths, drive letters
  and any `..` segment are rejected, so a hostile ZIP cannot escape
  `Agents/skills/<id>/`.
- Files from a skill bundle are never executed.
- In unattended mode (`ARC_SKILLS_SKILLS`), overwriting still requires
  `ARC_SKILLS_FORCE=1` - the prompts are never silently taken as yes.
