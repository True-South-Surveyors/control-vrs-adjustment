# Automatic tests for the team safety checks: the guard hook (as .claude/settings.json runs it,
# including its quick filter) and .githooks/pre-push.
# Run from the repo folder:  powershell -NoProfile -ExecutionPolicy Bypass -File .claude/hooks/guard-tests.ps1
# It builds throwaway repos in the temp folder, hands each check the commands below, and compares
# its answer with the expected one. Nothing is committed or pushed in this repo, and nothing is sent
# to GitHub. The merge approval checks need GitHub, so only the ones decided before that are here.
# Every problem a review finds in a safety check gets a case here, so it can't come back.

$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$prePush = Join-Path $repo '.githooks\pre-push'
$env:CLAUDE_PROJECT_DIR = $repo
# Ignores this computer's own git settings that could stop or stall the setup commits.
$gitTest = @('-c', 'user.name=Test', '-c', 'user.email=test@example.com', '-c', 'core.hooksPath=.none', '-c', 'commit.gpgsign=false')

# Git Bash, which Claude Code runs hooks with (and git's sh, which runs pre-push): the one Claude
# Code is told to use, or the one in the Git folder that git.exe sits in (up to two folders up).
$bash = $env:CLAUDE_CODE_GIT_BASH_PATH
if (-not ($bash -and (Test-Path -LiteralPath $bash))) {
    $bash = $null
    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    $d = if ($gitCmd) { Split-Path -Parent $gitCmd.Source }
    for ($up = 0; $d -and -not $bash -and $up -le 2; $up++) {
        $found = Join-Path $d 'bin\bash.exe'
        if (Test-Path -LiteralPath $found) { $bash = $found }
        $d = Split-Path -Parent $d
    }
}
$sh = if ($bash) { Join-Path (Split-Path -Parent $bash) 'sh.exe' }
if (-not $bash -or -not (Test-Path -LiteralPath $sh)) {
    Write-Host 'FAIL: could not find Git Bash (bash.exe and sh.exe in Git''s bin folder), so nothing was tested.' -ForegroundColor Red
    exit 1
}

$root = Join-Path ([IO.Path]::GetTempPath()) ('guard-tests-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $root | Out-Null

# A throwaway repo with $commits empty commits on main, then switched to $branch.
function NewRepo([string]$name, [string]$branch, [int]$commits) {
    $d = Join-Path $root $name
    New-Item -ItemType Directory -Path $d | Out-Null
    git -C $d init -q -b main
    for ($i = 1; $i -le $commits; $i++) { git -C $d @gitTest commit -q --allow-empty -m "Commit $i" }
    if ($branch -ne 'main') { git -C $d switch -q -c $branch }
    (Get-Item -LiteralPath $d).FullName
}

# Starts $exe with $text as its input, written directly (a PowerShell pipe adds a Windows line ending
# that git and Claude Code never send). Finish waits for it and returns its output and exit code.
function StartWithInput([string]$exe, [string]$arguments, [string]$dir, [string]$text) {
    $psi = New-Object Diagnostics.ProcessStartInfo $exe
    $psi.Arguments = $arguments
    $psi.WorkingDirectory = $dir
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $proc = [Diagnostics.Process]::Start($psi)
    $proc.StandardInput.Write($text)
    $proc.StandardInput.Close()
    @{ Proc = $proc; Out = $proc.StandardOutput.ReadToEndAsync(); Err = $proc.StandardError.ReadToEndAsync() }
}
function Finish($run) {
    $run.Proc.WaitForExit()
    [pscustomobject]@{ Out = $run.Out.Result; Err = $run.Err.Result; Code = $run.Proc.ExitCode }
}

$failed = 0
$passed = 0
$expectedChecks = 0
function Check([string]$what, [string]$expected, [string]$got) {
    if ($got -eq $expected) { $script:passed++ }
    else { $script:failed++; Write-Host "FAIL: $what`n      expected $expected, got $got" -ForegroundColor Red }
}

try {
    # The guard's hook command exactly as .claude/settings.json has it, saved as a script for Git Bash.
    $settings = Get-Content -Raw -LiteralPath (Join-Path $repo '.claude\settings.json') | ConvertFrom-Json
    $entry = @($settings.hooks.PreToolUse | Where-Object { @($_.hooks | Where-Object { $_.command -match 'guard\.ps1' }).Count })[0]
    if (-not $entry) { throw 'no PreToolUse hook in .claude/settings.json runs guard.ps1' }
    $hookCmd = @($entry.hooks | Where-Object { $_.command -match 'guard\.ps1' })[0].command
    # Its matcher decides which commands Claude Code hands it: it must include Bash and PowerShell.
    foreach ($tool in 'Bash', 'PowerShell') {
        $expectedChecks++
        $sent = -not $entry.matcher -or $entry.matcher -eq '*' -or $tool -match "^($($entry.matcher))$"
        Check ".claude/settings.json sends $tool commands to the guard" 'yes' $(if ($sent) { 'yes' } else { 'no' })
    }
    $hookScript = Join-Path $root 'hook.sh'
    [IO.File]::WriteAllText($hookScript, $hookCmd + "`n")

    $folders = @{
        MAIN    = NewRepo 'on-main' 'main' 1
        FEATURE = NewRepo 'on-feature' 'feature-x' 1
        EMPTY   = NewRepo 'no-commits' 'main' 0
    }

    # Expected answer, shell (PS = PowerShell), folder the command starts in, command.
    # {MAIN} {FEATURE} are those folders' full paths; {NL} is a line break.
    $cases = @(
        # Commits and pushes on main are refused; reading and branching are fine.
        @('deny',  'PS',   'MAIN',    'git commit -m "Fix totals"'),
        @('deny',  'PS',   'MAIN',    'git commit --allow-empty --dry-run -m "Safety check test"'),
        @('deny',  'PS',   'MAIN',    'git push --dry-run origin main'),
        @('deny',  'PS',   'MAIN',    'git push'),
        @('deny',  'PS',   'MAIN',    'git push origin HEAD'),
        @('allow', 'PS',   'MAIN',    'git status'),
        @('allow', 'PS',   'MAIN',    'git pull'),
        @('allow', 'PS',   'MAIN',    'git switch main; git pull'),
        @('allow', 'PS',   'MAIN',    'git switch -c fix-report-totals'),
        @('allow', 'PS',   'MAIN',    'Get-ChildItem'),
        @('allow', 'PS',   'EMPTY',   'git commit -m "First commit"'),
        # Release tags are pushed from main.
        @('allow', 'PS',   'MAIN',    'git tag v1.2 abc1234'),
        @('allow', 'PS',   'MAIN',    'git push origin v1.2'),
        @('allow', 'PS',   'MAIN',    'git push --tags'),

        # Normal work on a feature branch.
        @('allow', 'PS',   'FEATURE', 'git commit -m "Fix totals"'),
        @('allow', 'PS',   'FEATURE', 'git commit -am "Fix totals"'),
        @('allow', 'PS',   'FEATURE', 'git commit --allow-empty -m "Start: x" -m "Planned files: y"'),
        @('allow', 'PS',   'FEATURE', 'git push'),
        @('allow', 'PS',   'FEATURE', 'git push -u origin feature-x'),
        @('allow', 'PS',   'FEATURE', 'git fetch origin; git merge --no-edit origin/main'),
        @('allow', 'PS',   'FEATURE', 'git branch -d old-branch'),
        @('allow', 'PS',   'FEATURE', 'gh pr create --title "WIP: x" --body "Planned files: y"'),
        @('allow', 'PS',   'FEATURE', 'gh pr list --json number,title,body,author,headRefName,files'),
        @('allow', 'PS',   'FEATURE', 'gh pr view 6'),

        # Pushing to main, or overwriting or deleting a branch on GitHub, from anywhere.
        @('deny',  'PS',   'FEATURE', 'git push origin main'),
        @('deny',  'PS',   'FEATURE', 'git push origin HEAD:main'),
        @('deny',  'PS',   'FEATURE', 'git push origin feature-x:refs/heads/main'),
        @('deny',  'PS',   'FEATURE', 'git push --force'),
        @('deny',  'PS',   'FEATURE', 'git push -f'),
        @('deny',  'PS',   'FEATURE', 'git push --force-with-lease'),
        @('deny',  'PS',   'FEATURE', 'git push origin +feature-x'),
        @('deny',  'PS',   'FEATURE', 'git push origin :feature-x'),
        @('deny',  'PS',   'FEATURE', 'git push --delete origin feature-x'),
        @('deny',  'Bash', 'FEATURE', '"/c/Program Files/Git/cmd/git.exe" push origin main'),

        # Skipping the git hooks, or switching them off.
        @('deny',  'PS',   'FEATURE', 'git commit --no-verify -m "x"'),
        @('deny',  'PS',   'FEATURE', 'git commit -n -m "x"'),
        @('deny',  'PS',   'FEATURE', 'git push --no-verify'),
        @('allow', 'PS',   'FEATURE', 'git commit -m "-n"'),
        @('allow', 'PS',   'FEATURE', 'git config core.hooksPath .githooks'),
        @('allow', 'PS',   'FEATURE', 'git config --get core.hooksPath'),
        @('deny',  'PS',   'FEATURE', 'git config core.hooksPath ""'),
        @('deny',  'PS',   'FEATURE', 'git config --unset core.hooksPath'),

        # Commands that can throw work away need a person's OK.
        @('ask',   'PS',   'FEATURE', 'git reset --hard origin/feature-x'),
        @('ask',   'PS',   'FEATURE', 'git clean -fd'),
        @('ask',   'PS',   'FEATURE', 'git branch -D old-branch'),
        @('ask',   'PS',   'FEATURE', 'git checkout -- .'),
        @('ask',   'PS',   'FEATURE', 'git stash drop'),

        # The folder a command really runs in.
        @('deny',  'PS',   'FEATURE', 'git -C "{MAIN}" commit -m "x"'),
        @('allow', 'PS',   'MAIN',    'git -C "{FEATURE}" commit -m "x"'),
        @('deny',  'PS',   'FEATURE', 'Set-Location "{MAIN}"; git commit -m "x"'),
        @('deny',  'Bash', 'FEATURE', 'cd "{MAIN}" && git commit -m "x"'),
        @('deny',  'Bash', 'FEATURE', 'cd "{MAIN}" && git push'),
        @('allow', 'Bash', 'MAIN',    'cd "{FEATURE}" && git push'),
        @('deny',  'PS',   'FEATURE', 'git -C $env:TEMP commit -m "x"'),
        @('deny',  'Bash', 'FEATURE', 'GIT_DIR=/c/x/.git git commit -m "x"'),

        # Git commands that are only text are not run; ones in another line or shell are.
        @('allow', 'PS',   'FEATURE', 'git commit -m "Explain why git push origin main is blocked"'),
        @('allow', 'Bash', 'FEATURE', 'git commit -m "$(cat <<''EOF''{NL}Fix it{NL}{NL}Don''t git push origin main.{NL}EOF{NL})"'),
        @('allow', 'PS',   'FEATURE', 'git status # then git push origin main'),
        @('deny',  'PS',   'FEATURE', 'git status{NL}git push origin main'),
        @('deny',  'Bash', 'FEATURE', 'bash -c "git push origin main"'),
        @('deny',  'Bash', 'FEATURE', 'bash -c ''git push origin main'''),

        # GitHub: read-only gh api, and merges only as a plain command on its own.
        @('allow', 'PS',   'FEATURE', 'gh api repos/o/r/pulls/5'),
        @('deny',  'PS',   'FEATURE', 'gh api repos/o/r/merges -X POST'),
        @('deny',  'PS',   'FEATURE', 'gh api repos/o/r/pulls/5 -f title=x'),
        @('deny',  'PS',   'FEATURE', 'gh api graphql -f query="mutation { x }"'),
        @('deny',  'PS',   'FEATURE', 'gh repo delete o/r --yes'),
        @('deny',  'PS',   'FEATURE', 'gh pr merge 5 --squash --admin'),
        @('deny',  'PS',   'FEATURE', 'gh pr merge 5 --squash -R o/r'),
        @('deny',  'PS',   'FEATURE', 'git status; gh pr merge 5 --squash')
    )

    $expectedChecks += $cases.Count
    $runs = foreach ($c in $cases) {
        $expected, $shell, $start, $command = $c
        $tool = if ($shell -eq 'PS') { 'PowerShell' } else { 'Bash' }
        foreach ($k in $folders.Keys) {
            $path = if ($tool -eq 'Bash') { $folders[$k] -replace '\\', '/' } else { $folders[$k] }
            $command = $command.Replace("{$k}", $path)
        }
        $command = $command.Replace('{NL}', "`n")
        $payload = @{ tool_name = $tool; cwd = $folders[$start]; tool_input = @{ command = $command } } | ConvertTo-Json -Compress
        # PowerShell 5.1 writes ' & < > as codes (backslash, u00 and two hex digits); Claude Code
        # sends them as they are.
        $payload = [regex]::Replace($payload, '\x5cu00(27|26|3c|3e)', { param($m) [string][char][Convert]::ToInt32($m.Groups[1].Value, 16) })
        @{ Expected = $expected; What = "guard, $tool in $start`: $command"; Dir = $folders[$start]; Payload = $payload }
    }
    # Eight at a time, since each case starts Git Bash and PowerShell.
    for ($i = 0; $i -lt $runs.Count; $i += 8) {
        $batch = @($runs[$i..([Math]::Min($i + 7, $runs.Count - 1))])
        $started = @($batch | ForEach-Object { StartWithInput $bash ('"' + ($hookScript -replace '\\', '/') + '"') $_.Dir $_.Payload })
        for ($j = 0; $j -lt $batch.Count; $j++) {
            $r = Finish $started[$j]
            # A crash, an error message or unreadable output counts as a failure, even when the
            # command should be allowed. PowerShell's own progress notes (CLIXML without errors) don't.
            $err = $r.Err.Trim()
            if ($err -match '^#< CLIXML' -and $err -notmatch 'S="Error"') { $err = '' }
            $got = if ($r.Code -ne 0 -or $err) { "an error (exit $($r.Code)): $err" }
                elseif (-not $r.Out.Trim()) { 'allow' }
                else {
                    try { ($r.Out | ConvertFrom-Json).hookSpecificOutput.permissionDecision }
                    catch { "output that isn't the hook's answer: $($r.Out.Trim())" }
                }
            Check $batch[$j].What $batch[$j].Expected $got
        }
    }

    # pre-push: git hands it one line per branch being pushed: local ref, local sha, remote ref, remote sha.
    $hist = NewRepo 'history' 'main' 2
    $b = (git -C $hist rev-parse HEAD) -as [string]
    $a = (git -C $hist rev-parse HEAD~1) -as [string]
    git -C $hist switch -q -c other $a
    git -C $hist @gitTest commit -q --allow-empty -m 'Other'
    $other = (git -C $hist rev-parse HEAD) -as [string]
    $zero = '0' * 40
    $pushes = @(
        @('blocked', "refs/heads/main $b refs/heads/main $a", 'update main'),
        @('blocked', "refs/heads/master $b refs/heads/master $a", 'update master'),
        @('blocked', "(delete) $zero refs/heads/main $a", 'delete main'),
        @('allowed', "refs/heads/main $b refs/heads/main $zero", 'create main in a new repo'),
        @('allowed', "refs/heads/feature-x $b refs/heads/feature-x $zero", 'new feature branch'),
        @('allowed', "refs/heads/feature-x $b refs/heads/feature-x $a", 'add commits to a feature branch'),
        @('blocked', "refs/heads/feature-x $other refs/heads/feature-x $b", 'overwrite commits on a feature branch')
    )
    $expectedChecks += $pushes.Count
    foreach ($p in $pushes) {
        $expected, $line, $what = $p
        $r = Finish (StartWithInput $sh ('"' + ($prePush -replace '\\', '/') + '" origin test') $hist "$line`n")
        Check "pre-push, $what" $expected $(if ($r.Code -eq 0) { 'allowed' } else { 'blocked' })
    }
} catch {
    $failed++
    Write-Host "FAIL: the tests stopped early: $_" -ForegroundColor Red
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if (-not $failed -and $passed -ne $expectedChecks) {
    $failed++
    Write-Host "FAIL: only $passed of $expectedChecks checks ran." -ForegroundColor Red
}
if ($failed) {
    Write-Host "$failed failed, $passed passed." -ForegroundColor Red
    exit 1
}
Write-Host "All $passed passed." -ForegroundColor Green
