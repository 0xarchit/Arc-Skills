& {
  # Arc Skills - ephemeral installer bootstrap.
  #
  #   irm https://skills.0xarchit.is-a.dev/install.ps1 | iex
  #
  # Fetches the registry, lets you pick skills, downloads the matching ZIPs from
  # the latest GitHub Release, verifies SHA-256, and unpacks them into
  # .\Agents\skills\<id>\. Nothing is installed globally. Nothing persists but
  # the skills you pick.
  #
  # Env: ARC_SKILLS_DIR       target directory (default .\Agents\skills)
  #      ARC_SKILLS_REPO      owner/repo (default 0xArchit/arc-skills)
  #      ARC_SKILLS_FORCE=1   overwrite without asking
  #      ARC_SKILLS_SKILLS    "react,nextjs" - skip the menu (unattended)
  #
  # Wrapped in a scriptblock on purpose: the helper functions die with their
  # scope instead of lingering in the caller's session after `iex`.

  $ErrorActionPreference = 'Stop'
  try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

  $Repo   = if ($env:ARC_SKILLS_REPO) { $env:ARC_SKILLS_REPO } else { '0xArchit/arc-skills' }
  $Dest   = if ($env:ARC_SKILLS_DIR) { $env:ARC_SKILLS_DIR } else { Join-Path (Get-Location).Path 'Agents\skills' }
  $Force  = ($env:ARC_SKILLS_FORCE -eq '1')
  $ApiUrl = if ($env:ARC_SKILLS_API) { $env:ARC_SKILLS_API } else { "https://api.github.com/repos/$Repo/releases/latest" }
  $DlBase = if ($env:ARC_SKILLS_DL) { $env:ARC_SKILLS_DL } else { "https://github.com/$Repo/releases/download" }
  $Tmp    = $null

  function Say-Ok   ($m) { Write-Host '  ' -NoNewline; Write-Host ([char]0x2713) -ForegroundColor Green -NoNewline; Write-Host " $m" }
  function Say-Dim  ($m) { Write-Host "  $m" -ForegroundColor DarkGray }
  function Say-Head ($m) { Write-Host ''; Write-Host "  $m" -ForegroundColor Cyan }
  function Fail     ($m) { throw $m }

  function Get-Text ($url) {
    $r = if ($PSVersionTable.PSVersion.Major -ge 6) { Invoke-WebRequest -Uri $url }
         else { Invoke-WebRequest -Uri $url -UseBasicParsing }
    # GitHub serves release assets as application/octet-stream, and PowerShell
    # hands those back as a byte array rather than a string. Without this the
    # JSON never parses and every lookup comes back empty.
    if ($r.Content -is [byte[]]) { [System.Text.Encoding]::UTF8.GetString($r.Content) }
    else { [string]$r.Content }
  }

  # Tolerate a UTF-8 BOM - editors on Windows add one, and ConvertFrom-Json
  # fails on it with a cryptic "Invalid JSON primitive".
  function Convert-Json ($text) {
    # The BOM is matched as the escape \uFEFF, never as a literal character:
    # Windows PowerShell decodes a BOM-less .ps1 as ANSI, so a literal U+FEFF
    # becomes three junk characters and the strip silently stops working.
    ($text -replace '^\uFEFF', '') | ConvertFrom-Json
  }

  function Get-File ($url, $out) {
    if ($PSVersionTable.PSVersion.Major -ge 6) { Invoke-WebRequest -Uri $url -OutFile $out }
    else { Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing }
  }

  # Get-FileHash is standard, but a polluted PSModulePath (some CI shells, conda,
  # VS Code terminals) can hide it - fall back to the .NET API.
  function Get-Sha256 ($path) {
    if (Get-Command Get-FileHash -ErrorAction SilentlyContinue) {
      return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLower()
    }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([System.IO.File]::ReadAllBytes($path)))).Replace('-', '').ToLower() }
    finally { $sha.Dispose() }
  }

  # Rejects absolute paths, drive letters and any `..` segment.
  function Assert-SafeArchive ($zipPath) {
    try { Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue } catch { }
    $archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
      foreach ($entry in $archive.Entries) {
        $n = $entry.FullName -replace '\\', '/'
        if ($n -match '^/' -or $n -match '^[A-Za-z]:' -or ($n -split '/') -contains '..') {
          throw "Unsafe path in archive: $($entry.FullName)"
        }
      }
    } finally { $archive.Dispose() }
  }

  function Show-Menu ($Skills) {
    $HasConsole = $true
    try { $null = [Console]::KeyAvailable } catch { $HasConsole = $false }
    if (-not $HasConsole) { return (Show-MenuPlain $Skills) }

    $selected = @{}
    $cursor   = 0
    $filter   = ''

    while ($true) {
      $view = @($Skills | Where-Object {
        $filter -eq '' -or ("$($_.id) $($_.name) $($_.category) $($_.description) $($_.tags -join ' ')".ToLower().Contains($filter))
      })
      if ($view.Count -gt 0 -and $cursor -ge $view.Count) { $cursor = $view.Count - 1 }
      if ($cursor -lt 0) { $cursor = 0 }

      Clear-Host
      Write-Host ''
      Write-Host '  ARC SKILLS' -ForegroundColor Cyan
      Write-Host ''
      Say-Dim "Available skills ($($Skills.Count))"
      Say-Dim '--------------------------------------'
      Write-Host ''
      for ($i = 0; $i -lt $view.Count; $i++) {
        $s    = $view[$i]
        $mark = if ($selected[$s.id]) { 'x' } else { ' ' }
        if ($i -eq $cursor) {
          Write-Host '  ' -NoNewline; Write-Host '>' -ForegroundColor Cyan -NoNewline
          Write-Host " [$mark] " -NoNewline
          Write-Host $s.name.PadRight(22) -NoNewline
          Write-Host " $($s.category)" -ForegroundColor DarkGray
        } else {
          Write-Host "    [$mark] $($s.name.PadRight(22))" -NoNewline
          Write-Host " $($s.category)" -ForegroundColor DarkGray
        }
      }
      if ($view.Count -eq 0) { Write-Host '    (no matches)' }
      Write-Host ''
      Say-Dim 'up/down move   space select   a all   / search   enter install   q quit'
      if ($filter) { Write-Host "  filter: $filter" -ForegroundColor DarkGray }

      $key = [Console]::ReadKey($true)
      switch ($key.Key) {
        'UpArrow'   { if ($view.Count) { $cursor = if ($cursor -gt 0) { $cursor - 1 } else { $view.Count - 1 } } }
        'DownArrow' { if ($view.Count) { $cursor = if ($cursor -lt $view.Count - 1) { $cursor + 1 } else { 0 } } }
        'Spacebar'  { if ($view.Count) { $id = $view[$cursor].id; $selected[$id] = -not $selected[$id] } }
        'Enter'     {
          $picked = @($Skills | Where-Object { $selected[$_.id] } | ForEach-Object { $_.id })
          if ($picked.Count -eq 0 -and $view.Count -gt 0) { $picked = @($view[$cursor].id) }
          if ($picked.Count -gt 0) { return $picked }
        }
        'Escape'    { Write-Host ''; return @() }
        default {
          if ($key.KeyChar -eq 'q' -or $key.KeyChar -eq 'Q') { Write-Host ''; return @() }
          if ($key.KeyChar -eq 'a' -or $key.KeyChar -eq 'A') { foreach ($s in $view) { $selected[$s.id] = $true } }
          if ($key.KeyChar -eq '/') {
            Write-Host ''
            Write-Host '  Search: ' -NoNewline
            $filter = (Read-Host).ToLower()
            $cursor = 0
          }
        }
      }
    }
  }

  # Fallback for hosts without a usable console (ISE, redirected input).
  function Show-MenuPlain ($Skills) {
    Write-Host ''
    for ($i = 0; $i -lt $Skills.Count; $i++) { Write-Host ("  {0}. {1}" -f ($i + 1), $Skills[$i].name) }
    Write-Host ''
    $answer = Read-Host '  Select (numbers, comma separated, q to quit)'
    if ($answer -eq 'q') { return @() }
    $picked = @()
    foreach ($part in $answer -split ',') {
      $n = 0
      if ([int]::TryParse($part.Trim(), [ref]$n) -and $n -ge 1 -and $n -le $Skills.Count) {
        $picked += $Skills[$n - 1].id
      }
    }
    return $picked
  }

  function Install-Skill ($id, $skill, $manifest, $tag) {
    $dest = Join-Path $Dest $id
    Write-Host ''
    Write-Host "  $($skill.name)" -ForegroundColor White

    if (Test-Path -LiteralPath $dest) {
      if ($Force) { Say-Ok 'replacing existing install (ARC_SKILLS_FORCE=1)' }
      else {
        Write-Host "  $($skill.name) is already installed. Overwrite? [y/N] " -NoNewline
        $a = Read-Host
        if ($a -notmatch '^[yY]') { Write-Host '  skipped'; return $true }
      }
      Remove-Item -LiteralPath $dest -Recurse -Force
    }

    $entry = $manifest.skills.$id
    if (-not $entry -or -not $entry.sha256) {
      Fail "$($skill.name) is not part of release $tag. Nothing was installed."
    }
    $asset = if ($entry.asset) { $entry.asset } else { "$id.zip" }
    $zip   = Join-Path $Tmp $asset

    Write-Host '  Downloading...'
    try { Get-File "$DlBase/$tag/$asset" $zip }
    catch { Fail "Download failed for $asset." }

    Write-Host '  Verifying...'
    $sha = Get-Sha256 $zip
    if ($sha -ne $entry.sha256.ToLower()) {
      Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
      Fail "Checksum verification failed (expected $($entry.sha256), got $sha). Nothing was installed."
    }
    Say-Ok 'SHA-256 verified'

    Write-Host '  Extracting...'
    try { Assert-SafeArchive $zip }
    catch {
      Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
      Fail "Unsafe paths in $asset - refusing to extract. Nothing was installed."
    }
    $stage = Join-Path $Tmp 'x'
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
    try { Expand-Archive -LiteralPath $zip -DestinationPath $stage -Force }
    catch { Fail "Could not extract $asset (invalid ZIP?)." }
    if (-not (Test-Path -LiteralPath (Join-Path $stage 'SKILL.md'))) {
      Fail "$asset contains no SKILL.md - not a skill bundle."
    }

    if (-not (Test-Path -LiteralPath $Dest)) { New-Item -ItemType Directory -Path $Dest -Force | Out-Null }
    Remove-Item -LiteralPath $dest -Recurse -Force -ErrorAction SilentlyContinue
    Move-Item -LiteralPath $stage -Destination $dest
    Say-Ok 'installed'
    return $true
  }

  try {
    Write-Host ''
    Write-Host '  ARC SKILLS' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  Checking releases... ' -NoNewline
    try { $tag = (Convert-Json (Get-Text $ApiUrl)).tag_name }
    catch { Fail "Could not find a release for $Repo ($($_.Exception.Message)).`n  Check your internet connection and try again." }
    if (-not $tag) { Fail "Could not find a release for $Repo." }
    Write-Host "`r  " -NoNewline; Write-Host ([char]0x2713) -ForegroundColor Green -NoNewline
    Write-Host " $tag"

    Write-Host '  Fetching skills... ' -NoNewline

    try { $registry = Convert-Json (Get-Text "$DlBase/$tag/registry.json") }
    catch { Fail "Could not fetch the skill registry from release $tag ($($_.Exception.Message)).`n  Check your internet connection and try again." }

    if (-not $registry -or -not $registry.skills) { Fail "Release $tag has no usable registry.json." }
    $skills = @($registry.skills)
    if ($skills.Count -eq 0) { Fail 'The registry lists no skills (invalid registry?).' }
    Write-Host "`r  " -NoNewline; Write-Host ([char]0x2713) -ForegroundColor Green -NoNewline
    Write-Host " $($skills.Count) skills available"

    if ($env:ARC_SKILLS_SKILLS) {
      $picked = @($env:ARC_SKILLS_SKILLS -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    } else {
      $picked = @(Show-Menu $skills)
    }
    if ($picked.Count -eq 0) { Write-Host ''; return }

    $chosen = @()
    foreach ($id in $picked) {
      $s = $skills | Where-Object { $_.id -eq $id } | Select-Object -First 1
      if (-not $s) { Fail "Unknown skill: $id" }
      $chosen += $s
    }

    Write-Host ''
    foreach ($s in $chosen) {
      Write-Host "  $($s.name)"
      Write-Host "    $($s.description)" -ForegroundColor DarkGray
    }

    if ($chosen.Count -gt 1) {
      Write-Host ''
      Write-Host "  Install $($chosen.Count) skills? [Y/n] " -NoNewline
      $a = Read-Host
      if ($a -match '^[nN]') { Write-Host ''; return }
    }


    try { $manifest = Convert-Json (Get-Text "$DlBase/$tag/manifest.json") }
    catch { Fail "Release $tag has no manifest.json - cannot verify downloads." }

    $Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("arc-skills-" + [System.IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Path $Tmp -Force | Out-Null

    $done = @(); $failed = @()
    foreach ($s in $chosen) {
      try { [void](Install-Skill $s.id $s $manifest $tag); $done += $s.id }
      catch { Write-Host ''; Write-Host "  $([char]0x2717) $($_.Exception.Message)" -ForegroundColor Red; $failed += $s.id }
    }

    Write-Host ''
    if ($done.Count -gt 0) {
      Write-Host '  Installed:'
      Write-Host ''
      foreach ($id in $done) { Say-Ok $id }
      Write-Host ''
      Write-Host '  Location:'
      Write-Host "  $Dest\"
    }
    if ($failed.Count -gt 0) {
      Write-Host ''
      Write-Host '  Failed:' -ForegroundColor Red
      foreach ($id in $failed) { Write-Host "  $([char]0x2717) $id" -ForegroundColor Red }
    }
    Write-Host ''
  }
  catch {
    Write-Host ''
    Write-Host "  $([char]0x2717) $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ''
  }
  finally {
    if ($Tmp -and (Test-Path -LiteralPath $Tmp)) {
      Remove-Item -LiteralPath $Tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}
