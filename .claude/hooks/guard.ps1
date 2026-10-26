# Team git rules for Claude Code. Runs before every shell command Claude makes.
# Free-plan stand-in for GitHub's paid branch protection; .githooks/pre-push is the second layer.
# Rules: no commits or pushes straight to main, no force pushes, no skipping checks,
# no destructive resets, and no merging a pull request until Claude has reviewed its latest commit
# and it includes everything already merged into main.

$payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
$cmd = [string]$payload.tool_input.command
if (-not $cmd) { exit 0 }
$cwd = [string]$payload.cwd
if (-not $cwd -or -not (Test-Path -LiteralPath $cwd)) { $cwd = $env:CLAUDE_PROJECT_DIR }

function Decide([string]$decision, [string]$reason) {
    @{ hookSpecificOutput = @{
        hookEventName            = 'PreToolUse'
        permissionDecision       = $decision
        permissionDecisionReason = $reason
    } } | ConvertTo-Json -Compress
    exit 0
}

function CurrentBranch([string]$dir) { (git -C $dir branch --show-current 2>$null) -as [string] }

$main = '(main|master)'

$isBash = [string]$payload.tool_name -eq 'Bash'

# One word of a command: a quoted string or a run of plain characters.
$word = '(?:"[^"]*"|''[^'']*''|[^\s;&|"'']+)'
# How a git command starts: git, git.exe or a quoted path to it (any capitals, Windows doesn't mind),
# then any options before the subcommand, such as -C <folder> or -c <setting>.
$git = '(?i:\bgit(\.exe)?["'']?(\s+-[^\s;&|]+(\s+' + $word + ')?)*\s+)'
# A command that changes folder, and the folder (group p).
$cdCmd = '(?i:cd|chdir|pushd|sl|Set-Location|Push-Location)\s+(?i:-(Literal)?Path\s+)?(?<p>' + $word + ')'

# A full path for $path, taken from $base. Empty if it can't be worked out (a variable in it, or no such folder).
function ResolveFolder([string]$path, [string]$base) {
    $quoted = $path -match '^["'']'
    $path = $path.Trim('"', "'")
    if (-not $path -or $path -match '[$%`*?]' -or $path -eq '-') { return '' }
    # A network share isn't followed: even looking at one can send this computer's login to that server.
    if ($path -match '^[\\/]{2}') { return '' }
    # Bash drops the backslashes from an unquoted path, so its cd would fail and the rest would run in the old folder.
    if ($isBash -and -not $quoted -and $path.Contains('\')) { return '' }
    if ($path -match '^~') { $path = $HOME + $path.Substring(1) }
    # Git Bash's own spellings of Windows folders (PowerShell can't use them).
    if ($isBash -and $path -match '^/tmp(/|$)') { $path = $env:TEMP + $path.Substring(4) }
    if ($isBash) { $path = $path -replace '^/([a-zA-Z])(/|$)', '$1:/' }
    if (-not [IO.Path]::IsPathRooted($path)) { $path = Join-Path $base $path }
    if (Test-Path -LiteralPath $path -PathType Container) { return (Resolve-Path -LiteralPath $path).Path }
    return ''
}

# Quoted text: PowerShell here-strings and Bash heredocs (<<'EOF' ... EOF) first, so a quote mark
# inside one doesn't end it, then "..." (which may hold a heredoc, as in "$(cat <<'EOF' ...)") and '...'.
# Inside "...", \" (Bash) or `" (PowerShell) is a quote mark that doesn't end it, and outside quotes
# an escaped character (such as the \' in Bash's 'it'\''s') doesn't start any.
$heredoc = '<<-?\s*[''"]?(?<eof>\w+)[''"]?[\s\S]*?\n\s*\k<eof>(?=\s|\)|$)'
$esc = if ($isBash) { '\\[\s\S]' } else { '`[\s\S]' }
$escape = if ($isBash) { $esc + '|[^"\\]' } else { $esc + '|[^"`]' }
$quoted = '@''[\s\S]*?\n''@|@"[\s\S]*?\n"@|' + $heredoc + '|"(?:' + $heredoc + '|' + $escape + ')*"|''[^'']*''|' + $esc
# A quoted git, or quoted path to it (starting C:, /, ~, . or a variable), is the git command itself rather than text.
$gitPath = '^(["''])(?i:(([a-z]:|[/~.$])[^"''\r\n]*[\\/])?git(\.exe)?)\1$'

# Comments: a # starting a word (or straight after ; & | or a bracket), outside quoted text, to the end of
# the line. They are only notes, and are taken out first so an apostrophe in one doesn't look like quoted
# text and a \ or ` ending one doesn't join it to the next line.
$cmd = [regex]::Replace($cmd, $quoted + '|(?<=^|[\s;&|(])#[^\r\n]*', [Text.RegularExpressions.MatchEvaluator]{
    param($m) if ($m.Value.StartsWith('#')) { '' } else { $m.Value }
})
# A line continuation (\ in Bash, ` in PowerShell, at the end of a line) joins the two lines.
$cmd = $cmd -replace '[\\`]\r?\n', ' '

# Text ending in a call to another shell with a command to run (bash -c, sh -lc, cmd /c, powershell -Command):
# the quoted text after it is commands, not a message, and is checked like the rest.
$wrapper = '(?i)\b(bash|sh|zsh|pwsh|powershell|cmd)(\.exe)?["'']?(\s+[-/][^\s"'']+(\s+[^-/\s"''][^\s"'']*)?)*\s+(-\w*c|-com\w*|/[ck])\s+$'
function Wrapped($m, [string]$s) { $s.Substring(0, $m.Index) -match $wrapper }
# Where the command has quoted text, such as a commit message or a PR title.
$quotes = @([regex]::Matches($cmd, $quoted) | Where-Object { $_.Value -notmatch $gitPath -and -not (Wrapped $_ $cmd) })
# $s with its quoted text blanked out to "", except a quoted git path or a quoted single plain word
# (such as "main", ".githooks" or '--no-verify'), which are left as git will see them, and a wrapped
# command, left without its quote marks. A word starting with - is still text when it is a message,
# title or body (git commit -m "-n").
function Unquote([string]$s) {
    [regex]::Replace($s, $quoted, [Text.RegularExpressions.MatchEvaluator]{
        param($m)
        if ($m.Value -match $gitPath) { return $m.Value }
        if ($m.Value -match '^["'']' -and (Wrapped $m $s)) { return ' ' + $m.Value.Substring(1, $m.Value.Length - 2) + "`n" }
        if ($m.Value -match '^(["''])([\w.:/\\=+@~,-]+)\1$') {
            $w = $Matches[2]
            if ($w -notmatch '^-' -or $s.Substring(0, $m.Index) -cnotmatch '(^|\s)(-[a-zA-Z]*[mFtb]|--(message|file|title|body|subject))(\s+|=)$') { return $w }
        }
        '""'
    })
}
$bare = Unquote $cmd
function InQuotes([int]$i) {
    foreach ($q in $quotes) { if ($i -gt $q.Index -and $i -lt $q.Index + $q.Length - 1) { return $true } }
    return $false
}

# Each git <sub> in the command (not ones only mentioned in quoted text), with the folder it will
# run in (Dir): the session folder, moved by any cd earlier in the command and by the git command's
# own -C options. Dir is empty if that can't be worked out.
function GitCalls([string]$sub) {
    $moved = $cmd -match '(^|[\s;&|])GIT_(DIR|WORK_TREE)=|\$env:GIT_(DIR|WORK_TREE)\b'
    foreach ($m in [regex]::Matches($cmd, $git + $sub + '(?![\w-])')) {
        if (InQuotes $m.Index) { continue }
        $dir = $cwd
        $before = $cmd.Substring(0, $m.Index)
        # A moved git folder, or a return to an earlier folder (popd), is more than the guard follows.
        if ($moved -or $m.Value -match '\s--(git-dir|work-tree)\b' -or
            $before -match '(?i)(^\s*|[;&|({\r\n]\s*)(popd|Pop-Location)\b') { $dir = '' }
        foreach ($cd in [regex]::Matches($before, '(^\s*|[;&|({\r\n"'']\s*)' + $cdCmd)) {
            if ($dir -and -not (InQuotes $cd.Groups['p'].Index)) { $dir = ResolveFolder $cd.Groups['p'].Value $dir }
        }
        foreach ($c in [regex]::Matches($m.Value, '(?<=\s)-C\s+(?<p>' + $word + ')')) {
            if ($dir) { $dir = ResolveFolder $c.Groups['p'].Value $dir }
        }
        # The rest of this git command, up to the next ; & | or line break: Rest with quoted text
        # blanked out (as in Unquote), Plain with just the quote marks taken away.
        $after = $cmd.Substring($m.Index + $m.Length)
        $rest = ((Unquote $after) -split '[;&|\r\n]')[0]
        $plain = ($after -split '[;&|\r\n]')[0] -replace '["'']', ''
        [pscustomobject]@{ Dir = $dir; Rest = $rest; Plain = $plain }
    }
}

$unknownFolder = 'Team rule: could not tell which folder this git command runs in, so could not check that it is not on main. For another folder, write its full path out with no variables such as $env:TEMP: git -C "<folder>" ..., or cd "<folder>" && ... (Bash), or Set-Location "<folder>"; ... (PowerShell).'

# The owner/name of the GitHub repo a folder belongs to, or empty. Its origin address is enough when
# that is $expected; otherwise GitHub is asked, which follows a repo that has moved (a copy made
# before a transfer still has the old address).
function OriginRepo([string]$dir, [string]$expected) {
    $local = ''
    $url = (git -C $dir remote get-url origin 2>$null) -as [string]
    if ($url -match 'github\.com[:/]+([^/]+/[^/]+?)(\.git)?/*$') { $local = $Matches[1] }
    if ($local -and $local -eq $expected) { return $local }
    try {
        Push-Location -LiteralPath $dir -ErrorAction Stop
        $name = (& gh repo view --json nameWithOwner --jq .nameWithOwner 2>$null) -as [string]
        if ($LASTEXITCODE -eq 0 -and $name -match '^[^/\s]+/[^/\s]+$') { return $name }
    } catch {
    } finally {
        Pop-Location -ErrorAction SilentlyContinue
    }
    return $local
}

# --no-verify (or any shortening git accepts, such as --no-verif) and git commit -n skip the git hooks.
if ($bare -match '--no-veri') {
    Decide 'deny' 'Team rule: --no-verify skips the safety checks. Fix whatever the check is complaining about instead.'
}
$commits = @(GitCalls 'commit')
foreach ($c in $commits) {
    # -n among git commit's short options, before any that takes a value (-m, -F, -C, -c, -t, -u, -S).
    if ($c.Rest -cmatch '\s-((?![mFCcutS])[a-zA-Z])*n') {
        Decide 'deny' 'Team rule: git commit -n is --no-verify, which skips the safety checks. Fix whatever the check is complaining about instead. (If -n was only text in the commit message, put the message in a file in $env:TEMP and use git commit -F <file>.)'
    }
}
# Every hooksPath given a value must be given .githooks; reading it is fine, removing it isn't.
$hooksSet = $bare -match 'hooksPath(\s+|\s*=\s*)(?!\.githooks/?(?=$|[\s;&|)])|[*\d]?>)[^\s;&|)]'
$hooksUnset = $bare -match '(--unset(-all)?|\bconfig\s+unset)\s+(-\S+\s+)*\S*hooksPath|--remove-section\s+core\b'
if ($hooksSet -or $hooksUnset) {
    Decide 'deny' 'Team rule: the git hooks path must stay .githooks (it holds the push safety check).'
}

foreach ($p in GitCalls 'push') {
    if ($p.Rest -match '\s(--force|--force-with-lease|--force-if-includes|--mirror|--delete)\b' -or
        $p.Rest -cmatch '\s-[a-zA-Z]*[fd]\b' -or
        $p.Rest -match '\s[+:]\S') {
        Decide 'deny' 'Team rule: no force pushes or remote branch deletion. If the push was rejected, run git fetch origin then git merge --no-edit origin/<branch>, then push again.'
    }
    if ($p.Plain -match ('\s(\S+:)?(refs/heads/)?' + $main + '(\s|$)')) {
        Decide 'deny' 'Team rule: never push to main. Push a feature branch and open a pull request.'
    }
    # It pushes the current branch unless it pushes only tags, or names a remote and a branch, other
    # than HEAD or @ (a branch worked out when it runs, such as $(git branch --show-current), counts as current).
    $names = @($p.Rest.Trim() -split '\s+' | Where-Object { $_ -and $_ -notmatch '^(-|\d?>)' })
    $current = $p.Rest -notmatch '\s--tags\b' -and ($names.Count -lt 2 -or
        @($names | Select-Object -Skip 1 | Where-Object { $_ -match '^\+?(HEAD|@)?(:|$)|[$`]|""' }).Count -gt 0)
    if ($current) {
        if (-not $p.Dir) { Decide 'deny' $unknownFolder }
        if ((CurrentBranch $p.Dir) -match "^$main$") {
            Decide 'deny' 'Team rule: you are on main. Create a feature branch (git switch -c <name>), then push that.'
        }
    }
}

foreach ($c in $commits) {
    if (-not $c.Dir) { Decide 'deny' $unknownFolder }
    if ((CurrentBranch $c.Dir) -match "^$main$") {
        git -C $c.Dir rev-parse --verify HEAD 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Decide 'deny' 'Team rule: never commit on main. Create a feature branch first (git switch -c <short-description>), then commit there.'
        }
    }
}

if ($bare -match ($git + 'reset\b.*--hard') -or
    $bare -match ($git + 'clean\b.*\s-[a-zA-Z]*f') -or
    $bare -cmatch ($git + 'branch\b.*\s-D\b') -or
    $bare -match ($git + '(checkout|restore)\s+(--\s+)?\.(\s|$)') -or
    $bare -match ($git + 'stash\s+(drop|clear)\b') -or
    $bare -match ($git + '(filter-branch|filter-repo)\b')) {
    Decide 'ask' 'This git command can permanently throw away work. Only approve it if you are sure.'
}

if ($bare -match '\bgh\s+repo\s+(delete|archive|rename)\b' -or $bare -match '\bgh\s+repo\s+edit\b.*--visibility') {
    Decide 'deny' 'Team rule: deleting, archiving, renaming or changing visibility of a repo is done by a person on github.com.'
}

# gh api is read-only here: it can write files, move branches or merge on GitHub, skipping every check below.
if ($cmd -match '\bgh(\.exe)?["'']?\s+api\b') {
    $graphql = $cmd -match '\bgh(\.exe)?["'']?\s+api\s+graphql\b'
    $apiCalls = ([regex]::Matches($cmd, '\bgh(\.exe)?["'']?\s+api\b')).Count
    # Field flags make gh api send a POST unless -X GET is given (only trusted when there is a single call).
    # gh fields are always key=value, which tells them apart from -f in other tools or in text.
    $fields = $cmd -cmatch '[\s"''](-i?[fF]=?\s*["'']?[^\s="'']+["'']?=|(--field|--raw-field)(\s|=)|--input(\s|=|$))'
    $explicitGet = $apiCalls -eq 1 -and $cmd -match '\bgh(\.exe)?["'']?\s+api\b[^;&|\r\n"'']*(-X|--method)[\s=]*["'']?GET\b'
    $write = ($graphql -and $cmd -match '(\bmutation\b|=@|--input|\$\(|`|(\b|(?<=-[fF]))query=["'']?\$)') -or
        $cmd -match '(-X|--method)[\s=]*["'']?(POST|PUT|PATCH|DELETE)\b' -or
        ((-not $graphql -or $apiCalls -gt 1) -and $fields -and -not $explicitGet)
    if ($write) {
        Decide 'deny' 'Team rule: gh api is read-only here. Change code through a reviewed pull request; anything else on GitHub is done by a person on github.com. If the command only mentions gh api in text, such as a PR comment, put that text in a file in $env:TEMP and pass it with --body-file.'
    }
}

if ($cmd -match '\bgh(\.exe)?["'']?\s+(?:-\S+\s+(?:[^-\s]\S*\s+)?){0,3}pr\s+(?:-\S+\s+(?:[^-\s]\S*\s+)?){0,3}merge\b') {
    if ($cmd -match '--admin') {
        Decide 'deny' 'Team rule: --admin bypasses the rules. Merge normally.'
    }
    if ($cmd -cmatch '\bgh(\.exe)?["'']?[^;&|\r\n]*\s(-R|--repo)(\s|=|$)') {
        Decide 'deny' 'Team rule: run the merge from inside the repo folder, without -R/--repo.'
    }
    # The merge must be a command on its own, so nothing rides along unchecked
    # (a second merge, a cd into another repo, GH_REPO=...). The one exception is a single cd into
    # another repo's folder first, written out in full, which is the folder checked below.
    $merge = $cmd.Trim() -replace '\s+2>&1$', ''
    if ($merge -notmatch ('^(' + $cdCmd + '\s*(&&|;)\s*)?gh(\.exe)?\s+pr\s+merge\b(?<args>[^;&|\r\n`$()"'']*)$')) {
        Decide 'deny' 'Team rule: run gh pr merge as a command on its own with plain arguments (no quotes, nothing chained before or after it), so the review check sees exactly what will be merged. To merge in another repo''s folder, the only thing allowed before it is one cd to that folder''s full path: cd "<folder>" && gh pr merge ... (Bash) or Set-Location "<folder>"; gh pr merge ... (PowerShell). If the command only mentions it in text, such as a commit message, put that text in a file in $env:TEMP (git commit -F <file>).'
    }
    $argText = $Matches['args']
    $mergeDir = $cwd
    if ($Matches['p']) {
        $mergeDir = ResolveFolder $Matches['p'] $cwd
        if (-not $mergeDir) {
            Decide 'deny' 'Team rule: could not find the folder this merge changes into. Write its full path out, with no variables such as $env:TEMP.'
        }
    }
    # Work out which PR is being merged, wherever its number sits among the flags.
    $tokens = @($argText.Trim() -split '\s+' | Where-Object { $_ })
    $target = ''
    $headArg = ''
    for ($i = 0; $i -lt $tokens.Count; $i++) {
        $t = $tokens[$i]
        if ($t -cmatch '^(-R|--repo)') {
            Decide 'deny' 'Team rule: run the merge from inside the repo folder, without -R/--repo.'
        }
        if ($t -match '^--match-head-commit=(.*)$') { $headArg = $Matches[1]; continue }
        if ($t -eq '--match-head-commit') { $i++; if ($i -lt $tokens.Count) { $headArg = $tokens[$i] }; continue }
        if ($t -cmatch '^(-t|--subject|-b|--body|-F|--body-file|-A|--author-email)$') { $i++; continue }
        if ($t -like '-*' -or $t -match '[<>]') { continue }
        if ($target) {
            Decide 'deny' 'Team rule: name exactly one pull request to merge.'
        }
        $target = $t
    }
    $viewArgs = @('pr', 'view') + $(if ($target) { @($target) } else { @() }) + @('--json', 'number,state,headRefOid,headRefName,baseRefName,title,url,comments')
    $ok = $false
    $behind = ''
    try {
        Push-Location -LiteralPath $mergeDir -ErrorAction Stop
        # gh prints UTF-8; without this, non-English text and byte-order marks arrive garbled.
        try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false } catch {}
        $json = & gh @viewArgs 2>$null
        $ok = $LASTEXITCODE -eq 0
        if ($ok -and $json) {
            $pr = ($json -join "`n") | ConvertFrom-Json
            $prRepo = if ($pr.url -match 'github\.com/([^/]+/[^/]+)/pull/') { $Matches[1] } else { '' }
            # How many commits the base branch has that this PR's latest commit doesn't (someone else merged first).
            if ($prRepo) {
                $behind = [string](& gh api "repos/$prRepo/compare/$($pr.baseRefName)...$($pr.headRefOid)?per_page=1" --jq '.behind_by' 2>$null)
            }
        }
    } catch {
    } finally {
        Pop-Location -ErrorAction SilentlyContinue
    }
    if (-not $ok -or -not $json) {
        Decide 'deny' 'Could not look up the pull request with gh to confirm it was reviewed. Check gh is installed and signed in (gh auth status).'
    }
    # The PR must belong to the repo of the folder being merged from (so the local-copy check below
    # looks at the right copy), and that repo to the same GitHub organisation as this session's repo.
    $folderRepo = OriginRepo $mergeDir $prRepo
    $sessionRepo = OriginRepo $(if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { $cwd }) $prRepo
    if (-not $prRepo -or $prRepo -ne $folderRepo -or -not $sessionRepo -or
        $prRepo.Split('/')[0] -ne $sessionRepo.Split('/')[0]) {
        Decide 'deny' "Team rule: merge a pull request only from a copy of its own repo, inside our GitHub organisation. Pull request: $($pr.url); folder: $mergeDir (its GitHub repo: $(if ($folderRepo) { $folderRepo } else { 'none found' }))."
    }
    if ($pr.state -ne 'OPEN') {
        Decide 'deny' "Pull request #$($pr.number) is already $($pr.state.ToLower()), so there is nothing to merge. If this branch has newer work, start again from step 1 on a new branch and bring across only the commits made after the PR was merged, with git cherry-pick."
    }
    if ($behind -notmatch '^\d+$') {
        Decide 'deny' "Could not check whether this pull request includes the latest $($pr.baseRefName). Check gh is signed in (gh auth status) and try again."
    }
    $base = $pr.baseRefName
    if ([int]$behind -gt 0) {
        Decide 'deny' "Team rule: $base has $behind newer commit(s) that this pull request does not include (someone else merged first). On the branch run git fetch origin then git merge --no-edit origin/$base, resolve any conflicts keeping both people's changes, re-test, push, then review again."
    }
    $short = $pr.headRefOid.Substring(0, 7)
    $approved = $pr.comments | Where-Object { $_.body -match "^[\s$([char]0xFEFF)]*Claude review: APPROVED for $($pr.headRefOid)\b" }
    if (-not $approved) {
        Decide 'deny' "Team rule: this pull request's latest commit ($short) has no Claude review approval. Run the review step from CLAUDE.md, fix what it finds, push, then post a comment whose first line is 'Claude review: APPROVED for $($pr.headRefOid)'."
    }
    if ($headArg -ne $pr.headRefOid) {
        Decide 'deny' "Team rule: add --match-head-commit $($pr.headRefOid) to the merge, so GitHub refuses it if anything is pushed to the branch after this check."
    }
    if ($pr.title -match '^\s*WIP\b') {
        Decide 'deny' 'Team rule: the pull request title still starts with WIP. Give it a final plain-English title (gh pr edit --title), since it becomes the commit message on main.'
    }
    # --delete-branch deletes this machine's copy of the PR branch: make sure nothing unpushed goes with it.
    $localRef = (git -C $mergeDir rev-parse --verify --quiet "refs/heads/$($pr.headRefName)" 2>$null) -as [string]
    $dirty = $null
    if ((CurrentBranch $mergeDir) -eq $pr.headRefName) { $dirty = git -C $mergeDir status --porcelain 2>$null }
    if ($dirty -or ($localRef -and $localRef -ne $pr.headRefOid)) {
        Decide 'deny' 'Team rule: this copy of the branch does not match GitHub (uncommitted changes, new files never added to git, unpushed commits, or commits from another machine it lacks). Sort that out, review again, then merge: commit and push only files that belong to this change; add generated output, test leftovers and personal files to .gitignore (or .git/info/exclude for this machine only); never commit client data; fetch and merge if GitHub is ahead.'
    }
    Decide 'ask' "Claude reviewed and approved commit $short of $prRepo pull request #$($pr.number), and it includes everything on $base. Approve promptly to merge it into ${base}; if you wait and the other person merges first, decline and ask Claude to merge again."
}

exit 0
