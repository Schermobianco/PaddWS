# Pubblica la versione web su GitHub Pages (https://schermobianco.github.io/PaddWS/): il contenuto
# di dist\paddws-X.Y.Z-web.zip diventa un commit nuovo del ramo gh-pages, figlio del precedente, e
# si invia. Il commit si costruisce con un indice temporaneo: il ramo attuale e i file di lavoro non
# cambiano. La prima volta attiva anche Pages sul ramo gh-pages. Lo chiama build_onforge.bat -Publish dopo
# la release; si può lanciare anche da solo, con lo zip della versione attuale in dist\.
# Uso:  powershell -File tools\publish-pages.ps1

$ErrorActionPreference = "Continue"   # git e gh scrivono su stderr anche quando va tutto bene
$root = (Resolve-Path "$PSScriptRoot\..").Path
$compilers = if ($env:PADDWS_COMPILERS) { $env:PADDWS_COMPILERS } else { "C:\DEV\@Compiler" }
$gh = Join-Path $compilers "gh\bin\gh.exe"
function Fail($msg) { Write-Host "ERRORE: $msg" -ForegroundColor Red; exit 1 }

Set-Location $root
$version = (Select-String -Path "$root\rust\Cargo.toml" -Pattern '^version = "(.*)"' | Select-Object -First 1).Matches[0].Groups[1].Value
$zip = Join-Path $root "dist\paddws-$version-web.zip"
if (-not (Test-Path $zip)) { Fail "$zip non c'è (build_onforge.bat)" }

# il sito: i file dello zip (che stanno in una cartella paddws-X.Y.Z-web) più .nojekyll, perché
# GitHub serva i file così come sono
$site = Join-Path $env:TEMP "paddws-pages"
if (Test-Path $site) { Remove-Item -Recurse -Force $site }
Expand-Archive $zip -DestinationPath $site
$inner = Get-ChildItem $site -Directory | Select-Object -First 1
if (-not $inner -or -not (Test-Path (Join-Path $inner.FullName "index.html"))) { Fail "nello zip non c'è index.html" }
$tree = $inner.FullName
New-Item -ItemType File (Join-Path $tree ".nojekyll") | Out-Null

# commit dal contenuto di $tree, figlio dell'ultimo gh-pages su GitHub se c'è già
git fetch -q origin gh-pages 2>$null
$parent = if ($LASTEXITCODE -eq 0) { (git rev-parse FETCH_HEAD).Trim() } else { $null }
$index = Join-Path $env:TEMP "paddws-pages.index"
if (Test-Path $index) { Remove-Item $index }
$env:GIT_INDEX_FILE = $index
git -c core.autocrlf=false --work-tree=$tree add -A .
$treeId = (git write-tree).Trim()
Remove-Item Env:GIT_INDEX_FILE
Remove-Item $index
if ($parent -and (git rev-parse "$parent^{tree}").Trim() -eq $treeId) {
    Write-Host "gh-pages è già la versione $version"
} else {
    $parentArgs = @(if ($parent) { "-p", $parent })
    # messaggio con -m: in una pipe PowerShell 5.1 gli metterebbe davanti il BOM
    $commitId = (git commit-tree $treeId @parentArgs -m "Versione web $version").Trim()
    if (-not $commitId) { Fail "commit della versione web" }
    git push -q origin "${commitId}:refs/heads/gh-pages"
    if ($LASTEXITCODE -ne 0) { Fail "push del ramo gh-pages" }
    Write-Host "gh-pages: versione web $version ($($commitId.Substring(0, 7)))"
}
Remove-Item -Recurse -Force $site

# Pages attivo sul ramo gh-pages (solo la prima volta serve crearlo)
& $gh api "repos/{owner}/{repo}/pages" *> $null
if ($LASTEXITCODE -ne 0) {
    & $gh api -X POST "repos/{owner}/{repo}/pages" -f "source[branch]=gh-pages" -f "source[path]=/" *> $null
    if ($LASTEXITCODE -ne 0) { Fail "attivazione di GitHub Pages" }
    Write-Host "GitHub Pages attivato sul ramo gh-pages"
}
& $gh api "repos/{owner}/{repo}/pages" --jq .html_url
