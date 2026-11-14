# Release in locale sulla macchina forge (tools\forge): questo PC manda i sorgenti del commit attuale,
# forge fa nei suoi container gli stessi controlli e gli stessi pacchetti delle GitHub Action (core
# MiSTer compreso) e questo PC li riprende in dist\. Sul PC servono solo git, ssh e, per pubblicare, gh.
# Se forge è spenta la accende (VMware, senza finestra) e alla fine la rispegne.
#
# Uso:  build_onforge.bat [-Publish | -PublishOnly] [-NoCheck] [-CheckOnly] [-SkipMister] [-KeepVm]
#                         [-WorkingTree [-Synth]]
#   -Publish     dopo la build pubblica la release vX.Y.Z su GitHub con gh (anteprima se la versione
#                ha un "-"): serve il tag vX.Y.Z sul commit attuale, già inviato (tools/release.py e
#                git push); poi la versione web su GitHub Pages (tools\publish-pages.ps1)
#   -PublishOnly pubblica come -Publish i pacchetti già in dist\ (di una build senza -Publish, provati
#                prima), senza accendere forge né ricostruire: la release in due tempi è
#                tools/release.py, build_onforge.bat, le prove, git push --follow-tags, -PublishOnly
#   -NoCheck     senza i controlli; -CheckOnly solo i controlli (build_ongithub.bat)
#   -SkipMister  senza la sintesi del core MiSTer (circa 16 minuti)
#   -KeepVm      lascia forge accesa anche se l'ha accesa questo script
#   -WorkingTree i file come sono ora, modifiche e file nuovi compresi, senza commit: solo i
#                controlli (check_onforge.bat), lontano dall'antivirus di questo PC
#   -Synth       con -WorkingTree anche la sintesi del core MiSTer (ALM e slack), senza pacchetti
# Configurazione in forge.local.psd1 (non versionato), per esempio:
#   @{ Host = 'forge'; Vmx = 'D:\VM\forge\forge.vmx' }
# Host è il nome ssh di forge (~/.ssh/config); senza Vmx forge va accesa a mano.

param([switch]$Publish, [switch]$PublishOnly, [switch]$NoCheck, [switch]$CheckOnly, [switch]$SkipMister,
      [switch]$KeepVm, [switch]$WorkingTree, [switch]$Synth)

$ErrorActionPreference = "Continue"   # git, ssh e gh scrivono su stderr anche quando va tutto bene
$root = (Resolve-Path "$PSScriptRoot\..").Path
$dist = Join-Path $root "dist"
$compilers = if ($env:PADDWS_COMPILERS) { $env:PADDWS_COMPILERS } else { "C:\DEV\@Compiler" }
$gh = Join-Path $compilers "gh\bin\gh.exe"
$vmrun = "C:\Program Files\VMware\VMware Workstation\vmrun.exe"
function Fail($msg) { Write-Host "ERRORE: $msg" -ForegroundColor Red; exit 1 }
function Step($msg) { Write-Host "`n== $msg" -ForegroundColor Cyan }

Set-Location $root
$cfg = @{ Host = "forge" }
$cfgFile = Join-Path $root "forge.local.psd1"
if (Test-Path $cfgFile) { $cfg = Import-PowerShellDataFile $cfgFile }
$vm = $cfg.Host
$version = (Select-String -Path "$root\rust\Cargo.toml" -Pattern '^version = "(.*)"' | Select-Object -First 1).Matches[0].Groups[1].Value
$tag = "v$version"
$commit = (git rev-parse --short HEAD).Trim()
$source = "HEAD"
if ($WorkingTree) {
    if ($Publish) { Fail "-WorkingTree non pubblica: la release parte da un commit" }
    $CheckOnly = $true
    # albero dei file di adesso (anche quelli nuovi non ignorati), con i fine riga del repository,
    # da un indice temporaneo: l'indice vero e il ramo non cambiano
    $index = Join-Path $env:TEMP "paddws-forge.index"
    Copy-Item (Join-Path $root ".git\index") $index -Force
    $env:GIT_INDEX_FILE = $index
    git add -A 2>$null
    $source = (git write-tree).Trim()
    Remove-Item Env:GIT_INDEX_FILE
    Remove-Item $index
    $commit = "$commit+" + $source.Substring(0, 7)
} elseif ($Synth) {
    Fail "-Synth va con -WorkingTree (la release fa sempre la sintesi)"
}
Write-Host "PADD WS $version (commit $commit) su $vm"
# -PublishOnly non manda sorgenti a forge: le modifiche in corso non contano
if (-not $WorkingTree -and -not $PublishOnly -and (git status --porcelain)) { Fail "il repository ha modifiche non committate: forge riceve il commit, non i file modificati (per provarle: check_onforge.bat)" }
if ($PublishOnly) {
    if ($Publish -or $WorkingTree -or $CheckOnly) { Fail "-PublishOnly va da solo: pubblica i pacchetti già in dist" }
    $Publish = $true
    # i pacchetti in dist devono essere di questa versione (quelli del MiSTer hanno la data)
    $mine = @(Get-ChildItem $dist -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "paddws-$version-*" })
    if ($mine.Count -eq 0) { Fail "in $dist non ci sono i pacchetti della ${version}: prima build_onforge.bat" }
    $other = @(Get-ChildItem $dist -File | Where-Object { $_.Name -like "paddws-*" -and $_.Name -notlike "paddws-$version-*" })
    if ($other.Count -gt 0) { Fail "in $dist ci sono pacchetti di un'altra versione: $($other.Name -join ', ')" }
}
if ($Publish) {
    $at = git rev-list -n 1 $tag 2>$null
    if (-not $at -or $at.Trim() -ne (git rev-parse HEAD).Trim()) { Fail "il tag $tag non è sul commit attuale (python tools/release.py ...)" }
    if (-not (git ls-remote --tags origin $tag)) { Fail "il tag $tag non è su GitHub (git push --follow-tags)" }
}

# $sshOpts va in ogni ssh e scp: a volte il DHCP di VMware dà a forge un altro indirizzo (FollowIp)
$sshOpts = @()
function Reachable { ssh @sshOpts -o BatchMode=yes -o ConnectTimeout=5 $vm true 2>$null; return $LASTEXITCODE -eq 0 }
# se ssh non risponde, l'indirizzo di forge lo sa VMware (open-vm-tools): se è cambiato si usa quello
function FollowIp {
    if (-not $cfg.Vmx -or $script:sshOpts) { return }
    $ip = (& $vmrun -T ws getGuestIPAddress $cfg.Vmx 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $ip -notmatch '^\d+\.\d+\.\d+\.\d+$') { return }
    $known = (ssh -G $vm 2>$null | Where-Object { $_ -like 'hostname *' } | Select-Object -First 1) -replace '^hostname ', ''
    if ($ip -ne $known) {
        $script:sshOpts = @('-o', "HostName=$ip")
        Write-Host "  forge ora ha l'indirizzo $ip, non ${known}: conviene correggere HostName in ~/.ssh/config" -ForegroundColor Yellow
    }
}
$started = $false
if ($PublishOnly) {
    Step "pacchetti già in $dist"
    Get-ChildItem $dist -File | ForEach-Object { "  {0,-45} {1,10:N0} byte" -f $_.Name, $_.Length }
} elseif (-not (Reachable)) {
    if (-not $cfg.Vmx) { Fail "forge ($vm) non risponde e forge.local.psd1 non dice dov'è la VM (Vmx): va accesa a mano" }
    if (-not (Test-Path $vmrun)) { Fail "manca $vmrun (VMware Workstation)" }
    $vmxPath = (Resolve-Path $cfg.Vmx).Path
    if (& $vmrun -T ws list | Where-Object { $_ -ieq $vmxPath }) {
        Step "forge è accesa ma ssh non risponde"
    } else {
        Step "accensione di forge ($($cfg.Vmx))"
        & $vmrun -T ws start $cfg.Vmx nogui
        if ($LASTEXITCODE -ne 0) { Fail "vmrun non ha acceso la VM" }
        $started = $true
    }
    $t = 0
    while (-not (Reachable)) {
        FollowIp
        Start-Sleep -Seconds 5
        $t += 5
        if ($t -ge 180) { Fail "forge accesa ma ssh non risponde dopo 3 minuti" }
    }
    Write-Host "  pronta in circa $t s"
}

$ok = $PublishOnly
if (-not $PublishOnly) { try {
    Step "sorgenti del commit $commit su forge"
    # con i fine riga del repository (LF), come il checkout della CI; in un file e non in una pipe:
    # PowerShell 5 rovinerebbe i byte del tar
    $tar = Join-Path $env:TEMP "paddws-forge-$commit.tar"
    git -c core.autocrlf=false archive --format=tar -o $tar $source
    scp @sshOpts -q $tar "${vm}:forge/src.tar"
    if ($LASTEXITCODE -ne 0) { throw "copia dei sorgenti" }
    Remove-Item $tar
    # cartella nuova e scambio alla fine: la vista della console legge status.sh da lì
    ssh @sshOpts $vm "set -e; cd ~/forge; rm -rf src.new; mkdir src.new; tar -xf src.tar -C src.new; rm src.tar; echo 'commit $commit ($version)' > src.new/.source; rm -rf src; mv src.new src"
    if ($LASTEXITCODE -ne 0) { throw "estrazione dei sorgenti su forge" }

    $opts = @()
    if ($NoCheck) { $opts += "--no-check" }
    if ($CheckOnly) { $opts += "--check-only" }
    if ($SkipMister) { $opts += "--no-mister" }
    if ($Synth) { $opts += "--synth" }
    ssh @sshOpts $vm "sh ~/forge/src/tools/forge/build.sh $($opts -join ' ')"
    if ($LASTEXITCODE -ne 0) { throw "build su forge (forge-stato sulla VM per lo stato)" }

    if (-not $CheckOnly) {
        Step "pacchetti in $dist"
        if (Test-Path $dist) { Remove-Item -Recurse -Force $dist }
        New-Item -ItemType Directory $dist | Out-Null
        scp @sshOpts -q "${vm}:forge/out/*.zip" "${vm}:forge/out/*.tar.gz" $dist
        if ($LASTEXITCODE -ne 0) { throw "copia dei pacchetti da forge" }
        # l'immagine del Deck c'è solo se forge ha ~/forge/deck-cache (tools/forge/build.sh)
        scp @sshOpts -q "${vm}:forge/out/*.img.xz" $dist 2>$null
        Get-ChildItem $dist | ForEach-Object { "  {0,-45} {1,10:N0} byte" -f $_.Name, $_.Length }
    }
    $ok = $true
} catch {
    Write-Host "ERRORE: $_" -ForegroundColor Red
} finally {
    if ($started -and -not $KeepVm) {
        Step "spegnimento di forge"
        & $vmrun -T ws stop $cfg.Vmx soft
    }
} }
if (-not $ok) { exit 1 }

if ($Publish) {
    Step "release $tag su GitHub"
    # solo i file: le cartelle (un pacchetto estratto per provarlo) restano fuori
    $files = (Get-ChildItem $dist -File).FullName
    # note dal CHANGELOG (tools/release_notes.py): per le anteprime le voci nuove dal tag precedente
    $python = Join-Path $root ".venv\Scripts\python.exe"
    if (-not (Test-Path $python)) { $python = "python" }
    $notes = Join-Path $env:TEMP "paddws-notes-$version.md"
    & $python (Join-Path $PSScriptRoot "release_notes.py") $version --output $notes
    if ($LASTEXITCODE -ne 0) { Fail "note della release (tools/release_notes.py)" }
    & $gh release view $tag *> $null
    if ($LASTEXITCODE -eq 0) {
        & $gh release upload $tag @files --clobber
        if ($LASTEXITCODE -eq 0) { & $gh release edit $tag --notes-file $notes | Out-Null }
    } else {
        # @(...): un if che restituisce un array di un elemento lo srotola in una stringa, che @pre
        # passerebbe a gh un carattere alla volta
        $pre = @(if ($version.Contains("-")) { "--prerelease" })
        & $gh release create $tag @files --title $tag --notes-file $notes @pre
    }
    if ($LASTEXITCODE -ne 0) { Fail "pubblicazione della release" }
    Remove-Item $notes
    & $gh release view $tag --json url --jq .url
    # la versione web anche su GitHub Pages (tools\publish-pages.ps1)
    Step "versione web su GitHub Pages"
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "publish-pages.ps1")
    if ($LASTEXITCODE -ne 0) { Fail "pubblicazione su GitHub Pages" }
}
