# Controlli prima di un push con le GitHub Action, alternativa a check_onforge.bat per chi non ha la
# macchina forge: i file come sono ora (modifiche e file nuovi, senza commit) vanno in un commit
# temporaneo su un ramo check/..., le quattro Action (Rust, Python, C64, MiSTer con la sintesi)
# partono su quel ramo e lo script le segue fino alla fine, poi cancella il ramo.
#
# Uso:  check_ongithub.bat [-NoSynth] [-NoWait] [-Keep]
#   -NoSynth  senza la sintesi Quartus del core MiSTer (circa mezz'ora in meno)
#   -NoWait   avvia le Action ed esce; il ramo resta (da cancellare a mano a Action finite)
#   -Keep     non cancella il ramo alla fine
# Il ramo e il commit temporanei non toccano il ramo attuale, l'indice né i file. Il repository è
# pubblico: per qualche minuto i file non committati sono visibili su GitHub (i file esclusi da
# .gitignore e .git/info/exclude no). Sui rami le Action non pubblicano nulla: allegano i pacchetti
# alle release solo sui tag vX.Y.Z. Richiede gh in C:\DEV\@Compiler\gh (autenticato).

param([switch]$NoSynth, [switch]$NoWait, [switch]$Keep)

$ErrorActionPreference = "Continue"   # git e gh scrivono su stderr anche quando va tutto bene
$root = (Resolve-Path "$PSScriptRoot\..").Path
$compilers = if ($env:PADDWS_COMPILERS) { $env:PADDWS_COMPILERS } else { "C:\DEV\@Compiler" }
$gh = Join-Path $compilers "gh\bin\gh.exe"
function Fail($msg) { Write-Host "ERRORE: $msg" -ForegroundColor Red; exit 1 }
function Step($msg) { Write-Host "`n== $msg" -ForegroundColor Cyan }
Set-Location $root
if (-not (Test-Path $gh)) { Fail "manca $gh" }

# commit dei file come sono ora, con un indice temporaneo: indice, ramo e file restano come sono
Step "commit temporaneo dei file come sono ora"
$index = Join-Path $env:TEMP "paddws-check-index-$PID"
$env:GIT_INDEX_FILE = $index
git read-tree HEAD
git add -A
$tree = (git write-tree).Trim()
Remove-Item Env:\GIT_INDEX_FILE
Remove-Item $index -ErrorAction SilentlyContinue
if (-not $tree) { Fail "git write-tree" }
$head = (git rev-parse HEAD).Trim()
$changed = $tree -ne (git rev-parse "HEAD^{tree}").Trim()
$commit = if ($changed) {
    (git commit-tree $tree -p $head -m "Controlli su GitHub (file non committati)").Trim()
} else {
    $head
}
if (-not $commit) { Fail "git commit-tree" }
$branch = "check/" + (Get-Date -Format "yyyyMMdd-HHmmss")
Write-Host ("  {0} su {1}{2}" -f $commit.Substring(0, 7), $head.Substring(0, 7),
    $(if ($changed) { ", con le modifiche non committate" } else { ", nessuna modifica" }))

Step "invio del ramo $branch"
git push -q origin "${commit}:refs/heads/$branch"
if ($LASTEXITCODE -ne 0) { Fail "push del ramo $branch" }
function DropBranch {
    git push -q origin --delete $branch
    if ($LASTEXITCODE -eq 0) { Write-Host "  ramo $branch cancellato" }
}

Step "avvio delle Action"
foreach ($w in "rust.yml", "python.yml", "c64.yml", "mister.yml") {
    $extra = @(if ($w -eq "mister.yml" -and $NoSynth) { "-f", "synth=false" })
    & $gh workflow run $w --ref $branch @extra
    if ($LASTEXITCODE -ne 0) { DropBranch; Fail "avvio di $w" }
}

# le run del ramo (compaiono qualche secondo dopo l'avvio)
function BranchRuns { @(& $gh run list --branch $branch --limit 20 --json databaseId,workflowName,status,conclusion | ConvertFrom-Json) }
$runs = @()
for ($i = 0; $i -lt 24 -and $runs.Count -lt 4; $i++) {
    Start-Sleep -Seconds 5
    $runs = BranchRuns
}
if ($runs.Count -lt 4) { Write-Host "  partite solo $($runs.Count) Action su 4" -ForegroundColor Yellow }
if (-not $runs) { DropBranch; Fail "nessuna Action partita su $branch" }
$runs | ForEach-Object { "  {0,-8} {1}" -f $_.workflowName, $_.status }
if ($NoWait) {
    Write-Host "`nLe Action continuano su GitHub: $gh run list --branch $branch"
    Write-Host "A Action finite: git push origin --delete $branch"
    exit 0
}

$wait = if ($NoSynth) { "circa 15 minuti" } else { "con la sintesi MiSTer circa 45 minuti" }
Write-Host "  si aspetta la fine ($wait)..."
do {
    Start-Sleep -Seconds 60
    $runs = BranchRuns
    $open = @($runs | Where-Object { $_.status -ne "completed" })
} while ($open)

Step "esito"
$runs | ForEach-Object { "  {0,-8} {1}" -f $_.workflowName, $_.conclusion }
$failed = @($runs | Where-Object { $_.conclusion -ne "success" })
foreach ($r in $failed) {
    Write-Host "`n-- $($r.workflowName): ultime righe del job fallito" -ForegroundColor Yellow
    & $gh run view $r.databaseId --log-failed 2>&1 | Select-Object -Last 40
}
if ($Keep) { Write-Host "`n  il ramo $branch resta su GitHub" } else { DropBranch }
if ($failed) { Fail "Action non riuscite ($($failed.Count) su $($runs.Count))" }
Write-Host "`nTutte le Action sono riuscite" -ForegroundColor Green
