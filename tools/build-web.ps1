# Costruisce la versione web (WebAssembly) in rust/target/web: paddws.wasm, la pagina
# (rust/web, con sid_audio.js per la musica del SID), le icone e il JavaScript di miniquad e di
# quad-snd (le loro copie in rust/vendor).
# Uso:  .\tools\build-web.ps1            poi, per provarla:  .\tools\build-web.ps1 -Serve
# (-Serve avvia un server locale su http://localhost:8080 con Python; dal telefono sulla stessa
# rete si apre http://<indirizzo del PC>:8080). Gira anche nella CI (pwsh su Linux).

param([switch]$Serve)

$ErrorActionPreference = "Continue"   # cargo scrive su stderr anche quando va tutto bene
$root = (Resolve-Path "$PSScriptRoot/..").Path
if (-not $env:CI) { . "$root/tools/rust-env.ps1" | Out-Null }   # in locale: toolchain portable

Push-Location "$root/rust"
try {
    cargo build --release -p paddws --target wasm32-unknown-unknown
    if ($LASTEXITCODE -ne 0) { exit 1 }
    # il mq_js_bundle.js distribuito con macroquad 0.4.16 non parte: si compone dai sorgenti, gl.js
    # e audio.js delle nostre copie di miniquad e quad-snd (rust/vendor)
    $js = @((Get-Content "$root/rust/vendor/miniquad/js/gl.js" -Raw), (Get-Content "$root/rust/vendor/quad-snd/js/audio.js" -Raw))

    # cartella ricreata da zero: file rimasti da build vecchie finirebbero nello zip della release
    $out = "$root/rust/target/web"
    if (Test-Path $out) { Remove-Item -Recurse -Force $out }
    New-Item -ItemType Directory -Force $out | Out-Null
    Copy-Item "$root/rust/web/*" $out
    Set-Content "$out/mq_js_bundle.js" ($js -join "`n") -Encoding utf8 -NoNewline
    Copy-Item "$root/rust/target/wasm32-unknown-unknown/release/paddws.wasm" $out
    foreach ($n in 64, 180, 192, 512) { Copy-Item "$root/assets/icons/paddws_$n.png" "$out/icon-$n.png" }
    # service worker: versione del gioco e impronta del wasm, che cambiano a ogni build; il browser
    # vede un sw.js diverso, lo installa e butta le copie vecchie. Letto e scritto in UTF-8 senza BOM
    # (Get-Content di PowerShell 5.1 senza -Encoding rovinerebbe le lettere accentate dei commenti)
    $version = (Select-String -Path "$root/rust/Cargo.toml" -Pattern '^version = "(.*)"' | Select-Object -First 1).Matches[0].Groups[1].Value
    $hash = (Get-FileHash "$out/paddws.wasm" -Algorithm SHA256).Hash.Substring(0, 12).ToLower()
    $sw = (Get-Content "$out/sw.js" -Raw -Encoding utf8).Replace("__PADDWS_VERSION__", "$version-$hash")
    [System.IO.File]::WriteAllText("$out/sw.js", $sw, (New-Object System.Text.UTF8Encoding $false))
    Write-Host "Versione web in $out"
} finally {
    Pop-Location
}

if ($Serve) {
    python -m http.server 8080 --directory "$root/rust/target/web"
}
