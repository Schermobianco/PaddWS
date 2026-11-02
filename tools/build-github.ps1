# Release online, come prima di build.bat: le GitHub Action, avviate da qui sul tag, costruiscono
# tutti i pacchetti, sintesi del core MiSTer compresa, e li allegano alla release.
#
# Uso:  build_ongithub.bat VERSIONE [-NoCheck] [-NoWait]
#         VERSIONE: patch, minor, major, X.Y.Z o X.Y.Z-beta.N (come tools/release.py): controlli
#         locali, commit e tag della versione, push; poi segue le Action fino alla fine
#       build_ongithub.bat [-NoWait]
#         senza versione: il tag vX.Y.Z è già sul commit attuale (per esempio fatto quando le
#         Action erano ferme): lo invia se manca su GitHub, rilancia le Action fallite del tag
# I workflow non partono da soli (repository privato, minuti a pagamento): li avvia questo script
# sul tag con gh workflow run.
#   -NoCheck  salta i controlli locali (gli stessi della CI, da tools\build-release.ps1)
#   -NoWait   non aspetta la fine delle Action
# I controlli locali girano sulla macchina forge (build.bat -CheckOnly). Richiede gh in
# C:\DEV\@Compiler\gh (autenticato) e Python.

param([string]$Version, [switch]$NoCheck, [switch]$NoWait)

$ErrorActionPreference = "Continue"   # git e gh scrivono su stderr anche quando va tutto bene
$root = (Resolve-Path "$PSScriptRoot\..").Path
$compilers = if ($env:PADDWS_COMPILERS) { $env:PADDWS_COMPILERS } else { "C:\DEV\@Compiler" }
$gh = Join-Path $compilers "gh\bin\gh.exe"
function Fail($msg) { Write-Host "ERRORE: $msg" -ForegroundColor Red; exit 1 }
function Step($msg) { Write-Host "`n== $msg" -ForegroundColor Cyan }
Set-Location $root

if (git status --porcelain) { Fail "il repository ha modifiche non committate" }
if ($Version -and -not $NoCheck) {
    & "$root\tools\build-release.ps1" -CheckOnly
    if ($LASTEXITCODE -ne 0) { Fail "controlli locali" }
}
if ($Version) {
    Step "versione $Version"
    python tools\release.py $Version
    if ($LASTEXITCODE -ne 0) { Fail "tools/release.py" }
}
$v = (Select-String -Path "$root\rust\Cargo.toml" -Pattern '^version = "(.*)"' | Select-Object -First 1).Matches[0].Groups[1].Value
$tag = "v$v"
$at = git rev-list -n 1 $tag 2>$null
if (-not $at -or $at.Trim() -ne (git rev-parse HEAD).Trim()) { Fail "il tag $tag non è sul commit attuale: build_ongithub.bat VERSIONE per crearlo" }

Step "invio di main e $tag"
$remote = git ls-remote --tags origin $tag
git push origin HEAD:main
if ($LASTEXITCODE -ne 0) { Fail "push di main" }
if (-not $remote) {
    git push origin $tag
    if ($LASTEXITCODE -ne 0) { Fail "push del tag $tag" }
}

# le run del tag (una per workflow: Rust, Python, C64, MiSTer); i workflow partono solo a mano
function TagRuns { (& $gh run list --branch $tag --limit 20 --json databaseId,workflowName,status,conclusion | ConvertFrom-Json) }
$existing = @(TagRuns)
if ($existing) {
    Step "Action del tag $tag già presenti: si rilanciano quelle non riuscite"
    $failed = @($existing | Where-Object { $_.status -eq "completed" -and $_.conclusion -ne "success" })
    if (-not $failed) { Write-Host "  nessuna run da rilanciare" }
    foreach ($r in $failed) {
        & $gh run rerun $r.databaseId | Out-Null
        Write-Host "  $($r.workflowName): rilanciata ($($r.databaseId))"
    }
} else {
    Step "avvio delle Action sul tag $tag"
    foreach ($w in "rust.yml", "python.yml", "c64.yml", "mister.yml") {
        & $gh workflow run $w --ref $tag
        if ($LASTEXITCODE -ne 0) { Fail "avvio di $w" }
    }
}

Step "Action del tag $tag"
Start-Sleep -Seconds 20
$runs = @(TagRuns)
if (-not $runs) { Fail "nessuna Action partita per $tag" }
# job rifiutati in pochi secondi: minuti o fatturazione (Settings > Billing & plans)
$blocked = $runs | Where-Object { $_.status -eq "completed" -and $_.conclusion -eq "failure" } | Select-Object -First 1
if ($blocked) {
    $why = & $gh run view $blocked.databaseId 2>&1 | Select-String "not started|billing|spending" | Select-Object -First 1
    if ($why) { Fail "GitHub non avvia i job: $($why.Line.Trim()) - per costruire in locale: build.bat -Publish" }
}
$runs | ForEach-Object { "  {0,-8} {1}" -f $_.workflowName, $_.status }
if ($NoWait) { Write-Host "`nLe Action continuano su GitHub: $gh run list --branch $tag"; exit 0 }

Write-Host "  si aspetta la fine (la sintesi MiSTer dura circa mezz'ora)..."
do {
    Start-Sleep -Seconds 60
    $runs = @(TagRuns)
    $open = @($runs | Where-Object { $_.status -ne "completed" })
} while ($open)
$runs | ForEach-Object { "  {0,-8} {1}" -f $_.workflowName, $_.conclusion }
if ($runs | Where-Object { $_.conclusion -ne "success" }) { Fail "Action non riuscite: $gh run view --log-failed" }
Step "release $tag"
& $gh release view $tag --json url,assets --jq '.url, (.assets[] | "  \(.name)")'
