# Esegue la versione C64 in VICE (x64sc, senza finestra, a velocità massima tranne con -Wav), dalla
# cartuccia EasyFlash c64\build\$Prg.crt, e salva la schermata dopo `-Cycles` cicli. Uso:
#   .\c64\shot.ps1 OUT.png [-Cycles 15000000] [-Prg autostart] [-Sid 6581|8580] [-Wav OUT.wav] [-Write]
#   -Prg     nome della build (.\c64\build.ps1 -Name ...)
#   -Wav     registra il suono (WAV, 48 kHz) di tutta l'esecuzione con il SID scelto da -Sid
#   -Write   le scritture nella flash (la classifica) restano nel .crt all'uscita di VICE
# Richiede VICE in C:\DEV\@Compiler\vice (o PADDWS_COMPILERS).

param(
    [Parameter(Mandatory = $true)][string]$Out,
    [long]$Cycles = 15000000,
    [string]$Prg = "paddws",
    [ValidateSet("6581", "8580")][string]$Sid = "6581",
    [string]$Wav = "",
    [switch]$Write
)
$compilers = if ($env:PADDWS_COMPILERS) { $env:PADDWS_COMPILERS } else { "C:\DEV\@Compiler" }
$vice = Join-Path $compilers "vice\bin\x64sc.exe"
$file = Join-Path $PSScriptRoot "build\$Prg.crt"
$out = [System.IO.Path]::GetFullPath($Out)
Remove-Item $out -ErrorAction SilentlyContinue
$args = @("-default", "-sidmodel", $(if ($Sid -eq "8580") { "1" } else { "0" }))
if ($Wav) {
    # il dispositivo WAV al posto della scheda audio (niente dagli altoparlanti); in warp VICE non
    # registra, quindi si va a velocità normale
    $wavPath = [System.IO.Path]::GetFullPath($Wav)
    Remove-Item $wavPath -ErrorAction SilentlyContinue
    $args += @("-sound", "-sounddev", "wav", "-soundarg", $wavPath)
} else {
    $args += @("-warp", "-sounddev", "dummy")
}
if ($Write) { $args += "-easyflashcrtwrite" }
$args += @("-cartcrt", $file, "-limitcycles", "$Cycles", "-exitscreenshot", $out)
$p = Start-Process -FilePath $vice -ArgumentList $args -PassThru -WindowStyle Hidden
if (-not $p.WaitForExit(300000)) { $p.Kill(); Write-Host "VICE non ha finito in tempo"; exit 1 }
if (-not (Test-Path $out)) { Write-Host "schermata non salvata"; exit 1 }
Write-Host $out
