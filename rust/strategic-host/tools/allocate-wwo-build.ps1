$ErrorActionPreference = 'Stop'
$repo = 'repos/ryoumiyahayato/wwo/git'
$branch = 'heads/wwo-build-sequence'
$ref = "refs/$branch"

function Invoke-SequenceApi([string[]] $Arguments) {
    for ($retry = 0; $retry -lt 3; $retry++) {
        $response = & gh api @Arguments 2>&1
        if (!$LASTEXITCODE) { return $response }
        $detail = $response -join [Environment]::NewLine
        if ($detail -notmatch 'timeout|timed out|unexpected EOF|connection|HTTP 50[0234]') { break }
        if ($retry -lt 2) { Start-Sleep -Milliseconds (300 * ($retry + 1)) }
    }
    throw "Could not access the shared WWO build sequence. $detail"
}

function Read-SequenceHead {
    $refs = Invoke-SequenceApi @("$repo/matching-refs/$branch")
    ($refs | ConvertFrom-Json | Where-Object { $_.ref -eq $ref }).object.sha
}

for ($attempt = 0; $attempt -lt 5; $attempt++) {
    $head = Read-SequenceHead
    $number = 1L
    if ($head) {
        $parent = $head
        $body = Invoke-SequenceApi @("$repo/commits/$parent")
        $base = $body | ConvertFrom-Json
        if (($base.message -split "`n", 2)[0] -notmatch '^WWO Build ([1-9][0-9]*)$') {
            throw 'The shared WWO build sequence has an invalid head.'
        }
        $tree = $base.tree.sha
        $number = [long]$Matches[1] + 1L
    } else {
        $parent = Invoke-SequenceApi @("$repo/ref/heads/main", '--jq', '.object.sha')
        $tree = Invoke-SequenceApi @("$repo/commits/$parent", '--jq', '.tree.sha')
    }
    $reservation = Split-Path -Leaf $env:WWO_BUILD_RECEIPT
    $message = "WWO Build $number`n`nSource $env:WWO_BUILD_SOURCE`nReservation $reservation"
    $candidate = Invoke-SequenceApi @('--method', 'POST', "$repo/commits", '-f', "message=$message",
        '-f', "tree=$tree", '-f', "parents[]=$parent", '--jq', '.sha')
    if ($head) {
        # Two runners can read the same parent. Only its first child can fast-forward the ref.
        $result = & gh api --method PATCH "$repo/refs/$branch" -f "sha=$candidate" -F 'force=false' 2>&1
    } else {
        $result = & gh api --method POST "$repo/refs" -f "ref=$ref" -f "sha=$candidate" 2>&1
    }
    if (!$LASTEXITCODE) {
        # GitHub can accept a second identical commit as a successful no-op. The message
        # includes the per-invocation receipt name to distinguish concurrent reservations.
        Write-Output $number
        exit 0
    }
    $next = Read-SequenceHead
    if (!$next -or $next -eq $head) { throw "Cannot advance the shared WWO build sequence. $result" }
}
throw 'The shared WWO build sequence changed during every allocation attempt.'
