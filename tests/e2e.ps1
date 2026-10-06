# Offline end-to-end test for install.ps1 against a fake release tree served by a
# local HTTP server. No network, no GitHub account.
#
#   pwsh -NoProfile -File tests/e2e.ps1
#   powershell -NoProfile -File tests/e2e.ps1     # also runs on 5.1
#
# Requires python (used only to serve the fixture over http).

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$installer = Join-Path $root 'install/install.ps1'

$python = (Get-Command python -ErrorAction SilentlyContinue)
if (-not $python) { Write-Host 'python not found - skipping e2e.ps1'; exit 0 }
$python = $python.Source

function Get-Sha256 ($path) {
  if (Get-Command Get-FileHash -ErrorAction SilentlyContinue) {
    return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLower()
  }
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash([System.IO.File]::ReadAllBytes($path)))).Replace('-', '').ToLower() }
  finally { $sha.Dispose() }
}

$pass = 0; $fail = 0
function Ok  ($m) { $script:pass++; Write-Host "  [ok] $m" }
function No  ($m, $d) { $script:fail++; Write-Host "  [FAIL] $m"; Write-Host "     $d" }
function Check ($m, $expected, $actual) { if ("$expected" -eq "$actual") { Ok $m } else { No $m "expected [$expected] got [$actual]" } }
function Has   ($p, $m) { if (Test-Path -LiteralPath $p) { Ok $m } else { No $m "missing $p" } }
function Hasnt ($p, $m) { if (Test-Path -LiteralPath $p) { No $m "should not exist: $p" } else { Ok $m } }
function MatchOut ($m, $out, $needle) { if ($out -match [regex]::Escape($needle)) { Ok $m } else { No $m "output did not contain '$needle'" } }

# snapshot the shared temp root: only assert this run adds nothing
$tmpBefore = @(Get-ChildItem -Path $env:TEMP -Filter 'arc-skills-*' -ErrorAction SilentlyContinue).Count

$fix  = Join-Path $env:TEMP ("arcfix-"  + [guid]::NewGuid().ToString('N'))
$proj = Join-Path $env:TEMP ("arcproj-" + [guid]::NewGuid().ToString('N'))
$server = $null

try {
  New-Item -ItemType Directory -Force -Path (Join-Path $fix 'dl/v9.9.9'), $proj | Out-Null

  # ---- fixture ------------------------------------------------------------
  $src = Join-Path $fix 'src/react'
  New-Item -ItemType Directory -Force -Path (Join-Path $src 'references'), (Join-Path $src 'examples') | Out-Null
  @'
---
id: react
name: React
description: Fixture skill.
---
# React fixture
'@ | Set-Content -Path (Join-Path $src 'SKILL.md') -Encoding ascii
  'nested file' | Set-Content -Path (Join-Path $src 'references/checklist.md') -Encoding ascii
  'export const C = 1;' | Set-Content -Path (Join-Path $src 'examples/Counter.tsx') -Encoding ascii

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $reactZip  = Join-Path $fix 'dl/v9.9.9/react.zip'
  $dockerZip = Join-Path $fix 'dl/v9.9.9/docker.zip'
  $javaZip   = Join-Path $fix 'dl/v9.9.9/java.zip'
  [System.IO.Compression.ZipFile]::CreateFromDirectory($src, $reactZip)
  Copy-Item $reactZip $dockerZip

  # java.zip is a traversal attack: one entry escapes the install directory
  $z = [System.IO.Compression.ZipFile]::Open($javaZip, 'Create')
  $null = $z.CreateEntry('../evil.txt')
  $null = $z.CreateEntry('SKILL.md')
  $z.Dispose()

  @'
{ "version": 1, "skills": [
  { "id": "react",  "name": "React",  "description": "Fixture react.",  "category": "frontend", "tags": ["react", "ui"] },
  { "id": "docker", "name": "Docker", "description": "Fixture docker.", "category": "devops",   "tags": ["docker"] },
  { "id": "java",   "name": "Java",   "description": "Fixture java.",   "category": "backend",  "tags": ["java"] } ] }
'@ | Set-Content -Path (Join-Path $fix 'dl/v9.9.9/registry.json') -Encoding utf8
  # re-write with a deliberate UTF-8 BOM: hand-edited registries often carry one
  [System.IO.File]::WriteAllText((Join-Path $fix 'dl/v9.9.9/registry.json'),
      [System.IO.File]::ReadAllText((Join-Path $fix 'dl/v9.9.9/registry.json')),
      (New-Object System.Text.UTF8Encoding($true)))
  '{"tag_name":"v9.9.9"}' | Set-Content -Path (Join-Path $fix 'latest.json') -Encoding utf8

  $shaReact  = Get-Sha256 $reactZip
  $shaJava   = Get-Sha256 $javaZip
  $shaDocker = '0' * 64
  @"
{ "version": 1, "release": "v9.9.9", "skills": {
    "react":  { "asset": "react.zip",  "sha256": "$shaReact" },
    "docker": { "asset": "docker.zip", "sha256": "$shaDocker" },
    "java":   { "asset": "java.zip",   "sha256": "$shaJava" } } }
"@ | Set-Content -Path (Join-Path $fix 'dl/v9.9.9/manifest.json') -Encoding utf8

  # ---- server -------------------------------------------------------------
  $l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
  $l.Start(); $port = $l.LocalEndpoint.Port; $l.Stop()
  # Serve every fixture file as application/octet-stream, the way GitHub serves
  # release assets. A plain http.server answers .json as application/json, which
  # makes Invoke-WebRequest return a string and hides the byte-array path.
  @'
import functools, http.server, socketserver, sys

class Handler(http.server.SimpleHTTPRequestHandler):
    def guess_type(self, path):
        return "application/octet-stream"

socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(("127.0.0.1", int(sys.argv[1])),
                            functools.partial(Handler, directory=sys.argv[2])) as httpd:
    httpd.serve_forever()
'@ | Set-Content -Path (Join-Path $fix 'serve.py') -Encoding ascii

  $server = Start-Process -FilePath $python -ArgumentList (Join-Path $fix 'serve.py'), "$port", $fix `
            -PassThru -WindowStyle Hidden
  $probe = "http://127.0.0.1:$port/latest.json"
  $ready = $false
  for ($i = 0; $i -lt 60; $i++) {
    try {
      $wc = New-Object System.Net.WebClient
      $null = $wc.DownloadString($probe)
      $ready = $true; break
    } catch { Start-Sleep -Milliseconds 250 }
  }
  if (-not $ready) { throw "fixture server never came up on $probe" }

  function Invoke-Installer ($projDir, $skills, $force) {
        $env:ARC_SKILLS_API      = "http://127.0.0.1:$port/latest.json"
    $env:ARC_SKILLS_DL       = "http://127.0.0.1:$port/dl"
    $env:ARC_SKILLS_SKILLS   = $skills
    if ($force) { $env:ARC_SKILLS_FORCE = '1' } else { Remove-Item env:ARC_SKILLS_FORCE -ErrorAction SilentlyContinue }
    # Run in-process, the same way `irm ... | iex` does. Spawning a child would
    # depend on the parent's process cwd, which Set-Location does not update.
    Push-Location $projDir
    try { (& $installer 6>&1 | Out-String) } finally { Pop-Location }
  }

  Write-Host ''
  Write-Host 'happy path'
  $out = Invoke-Installer $proj 'react' $false
  Has (Join-Path $proj 'Agents/skills/react/SKILL.md') 'SKILL.md installed'
  Has (Join-Path $proj 'Agents/skills/react/references/checklist.md') 'nested references/ installed'
  Has (Join-Path $proj 'Agents/skills/react/examples/Counter.tsx') 'nested examples/ installed'
  MatchOut 'checksum verified message' $out 'SHA-256 verified'
  MatchOut 'summary printed' $out 'Installed:'

  Write-Host ''
  Write-Host 'target override'
  $env:ARC_SKILLS_DIR = Join-Path $proj 'custom'
  $null = Invoke-Installer $proj 'react' $false
  Has (Join-Path $proj 'custom/react/SKILL.md') 'ARC_SKILLS_DIR honoured'
  Remove-Item env:ARC_SKILLS_DIR -ErrorAction SilentlyContinue

  Write-Host ''
  Write-Host 'checksum mismatch'
  $out = Invoke-Installer $proj 'docker' $false
  MatchOut 'mismatch detected' $out 'Checksum verification failed'
  Hasnt (Join-Path $proj 'Agents/skills/docker') 'nothing installed on mismatch'

  Write-Host ''
  Write-Host 'path traversal'
  $out = Invoke-Installer $proj 'java' $false
  MatchOut 'traversal rejected' $out 'Unsafe paths'
  Hasnt (Join-Path $proj 'Agents/skills/java') 'nothing installed on traversal'
  Check 'no file escaped the install dir' '0' (Get-ChildItem -Path $proj -Recurse -Filter 'evil.txt' -ErrorAction SilentlyContinue).Count

  Write-Host ''
  Write-Host 'existing install'
  $marker = Join-Path $proj 'Agents/skills/react/MARKER'
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $marker) | Out-Null
  'keep me' | Set-Content $marker
  $out = Invoke-Installer $proj 'react' $true
  Hasnt $marker 'ARC_SKILLS_FORCE=1 replaces it'
  Has (Join-Path $proj 'Agents/skills/react/SKILL.md') 'replacement is complete'

  Write-Host ''
  Write-Host 'unknown skill'
  $out = Invoke-Installer $proj 'nope' $false
  MatchOut 'unknown id refused' $out 'Unknown skill: nope'

  Write-Host ''
  Write-Host 'temp cleanup'
  $left = @(Get-ChildItem -Path $env:TEMP -Filter 'arc-skills-*' -ErrorAction SilentlyContinue).Count
  Check 'no temp dirs left behind' $tmpBefore $left
}
finally {
  if ($server -and -not $server.HasExited) { Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue }
  Remove-Item -LiteralPath $fix, $proj -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host "$pass passed, $fail failed"
Write-Host ''
if ($fail -gt 0) { exit 1 }
