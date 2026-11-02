# Sintesi del core in locale, con lo stesso container Docker della GitHub Action MiSTer
# (Quartus Prime Lite 17.0.2, immagine fissata per digest in quartus-image.txt): serve solo Docker
# Desktop (backend WSL2), nessun account Altera/Intel. Il .rbf esce in mister\output_files\PaddWS.rbf.
# Uso:  .\mister\synth.ps1

$ErrorActionPreference = "Stop"
$mister = $PSScriptRoot
$image = (Get-Content (Join-Path $mister "quartus-image.txt") -TotalCount 1).Trim()
& docker run --rm -v "${mister}:/project" -w /project $image quartus_sh --flow compile PaddWS
if ($LASTEXITCODE -ne 0) { Write-Host "Sintesi fallita"; exit 1 }
$out = Join-Path $mister "output_files"
Select-String -Path (Join-Path $out "PaddWS.fit.summary") -Pattern "Logic utilization|Total registers|Total block memory bits|Total DSP Blocks|Total pins" | ForEach-Object { $_.Line }
$sta = Join-Path $out "PaddWS.sta.summary"
Select-String -Path $sta -Pattern "^(Type|Slack|TNS)" | ForEach-Object { $_.Line }
if (Select-String -Path $sta -Pattern "^Slack\s*:\s*-" -Quiet) {
    Write-Host "Timing non rispettato (slack negativo): vedi output_files\PaddWS.sta.summary"
    exit 1
}
Write-Host (Join-Path $out "PaddWS.rbf")
