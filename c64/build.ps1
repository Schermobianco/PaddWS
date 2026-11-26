# Assembla la versione C64 in c64\build. Il prodotto è la cartuccia EasyFlash:
#   paddws.crt         (tools/make_crt.py) l'avvio (src/crt.s), il programma, i caratteri della
#                      scelta dei bonus e le voci di CHALLENGE; la classifica si salva nella flash
# e i pezzi da cui nasce, che servono anche al banco di prova (rust/c64):
#   paddws.prg         il programma, con le etichette (paddws.lbl, formato VICE) e la mappa della
#                      memoria (paddws.map); da solo non parte, gira dalla cartuccia
#   paddws.prg.end     il finale di CHALLENGE (src/ending.s), che ld65 scrive a parte: nella
#                      cartuccia dal banco END_BANK
#   voice0-6.prg       i file voce di CHALLENGE (src/voice.s), uno per tipo di racchetta, e
#   voice7.prg         quello di OMEGA
#   paddws.prg.omega   il resto del banco di OMEGA (musiche, jukebox, entrata nella presentazione)
# Uso:  .\c64\build.ps1 [-Name paddws] [-Ntsc] [-Define SIMBOLO[=valore], ...]
#       (-Ntsc: la versione NTSC, a 60 frame e tick al secondo, in c64\build\ntsc: i parametri da
#       c64\gen\ntsc\params.inc, il simbolo NTSC per il resto)
#       (-Rotated: la versione con il campo girato, una cartuccia a sé, in c64\build\rotated (con
#       -Ntsc in c64\build\rotated\ntsc): i file di c64\gen\rotated prima degli altri, il simbolo
#       ROTATED per il resto)
#       (il nome dentro il .crt dice quale delle quattro è: PADD WS HORIZONTAL PAL, HORIZONTAL
#       NTSC, VERTICAL PAL (il campo girato), VERTICAL NTSC)
#       (-Name autostart -Define AUTOSTART: parte subito con una partita, per le schermate;
#       con anche AUTONEXT la partita è NEXT, con AUTOCHALLENGE CHALLENGE, dalle scelte; il
#       programma e la cartuccia prendono il nome dato)
# Richiede cc65 in C:\DEV\@Compiler\cc65 (o PADDWS_COMPILERS) e Python (.venv del repository, se
# no quello nel PATH).

param([string]$Name = "paddws", [switch]$Ntsc, [switch]$Rotated, [string[]]$Define = @())

$ErrorActionPreference = "Stop"
$c64 = $PSScriptRoot
$root = Split-Path $c64
$compilers = if ($env:PADDWS_COMPILERS) { $env:PADDWS_COMPILERS } else { "C:\DEV\@Compiler" }
$bin = Join-Path $compilers "cc65\bin"
$where = "build" + $(if ($Rotated) { "\rotated" } else { "" }) + $(if ($Ntsc) { "\ntsc" } else { "" })
$out = Join-Path $c64 $where
# NTSC: i file di c64\gen\ntsc prima di quelli di c64\gen, e il simbolo NTSC; il campo girato: i
# file di c64\gen\rotated (e c64\gen\rotated\ntsc) prima di tutti, e il simbolo ROTATED
$genNtsc = @(if ($Rotated -and $Ntsc) { "-I", "$c64\gen\rotated\ntsc" }) + @(if ($Rotated) { "-I", "$c64\gen\rotated" }) + @(if ($Ntsc) { "-I", "$c64\gen\ntsc" })
$binRot = @(if ($Rotated) { "--bin-include-dir", "$c64\gen\rotated" })
$tv = @(if ($Ntsc) { "-D", "NTSC" }) + @(if ($Rotated) { "-D", "ROTATED" })
$py = Join-Path $root ".venv\Scripts\python.exe"
if (-not (Test-Path $py)) { $py = "python" }
New-Item -ItemType Directory -Force $out | Out-Null

# Assembla src\$Src in $Base$Ext con la configurazione $Cfg (accanto $Base.o, .lst e con -Labels
# .lbl e .map); $Defs sono già coppie "-D", "SIMBOLO".
function Build-Part([string]$Src, [string]$Base, [string]$Ext, [string]$Cfg, [string[]]$Defs, [switch]$Labels) {
    $obj = Join-Path $out "$Base.o"
    & "$bin\ca65.exe" --cpu 6502 -g @Defs @tv -I "$c64\src" @genNtsc -I "$c64\gen" @binRot --bin-include-dir "$c64\gen" -o $obj -l "$out\$Base.lst" "$c64\src\$Src"
    if ($LASTEXITCODE -ne 0) { exit 1 }
    $link = @(if ($Labels) { "-Ln", "$out\$Base.lbl", "-m", "$out\$Base.map" })
    & "$bin\ld65.exe" -C "$c64\$Cfg" -o "$out\$Base$Ext" @link $obj
    if ($LASTEXITCODE -ne 0) { exit 1 }
}

$defs = @(); foreach ($d in $Define) { $defs += @("-D", $d) }
Build-Part "main.s" $Name ".prg" "paddws.cfg" $defs -Labels
$voices = @()
foreach ($k in 0..7) {
    Build-Part "voice.s" "voice$k" ".prg" "voice.cfg" @("-D", "VOICE_KIND=$k")
    $voices += "$out\voice$k.prg"
}
Build-Part "crt.s" "$Name-crt" ".bin" "crt.cfg" @()
$pads = @(if ($Rotated) { "--pads", "$c64\gen\rotated\paddles.bin" })
$crtName = "PADD WS " + $(if ($Rotated) { "VERTICAL" } else { "HORIZONTAL" }) + $(if ($Ntsc) { " NTSC" } else { " PAL" })
& $py "$root\tools\make_crt.py" @pads --name $crtName "$out\$Name.crt" "$out\$Name-crt.bin" "$out\$Name.prg" "$c64\gen\pick_bank.bin" "$out\$Name.prg.end" "$out\$Name.prg.omega" @voices | Out-Null
if ($LASTEXITCODE -ne 0) { exit 1 }
Write-Host "c64\$where\$Name.crt: cartuccia EasyFlash ($Name.prg per il banco di prova)"
