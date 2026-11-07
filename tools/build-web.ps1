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
    Write-Host "Versione web in $out"
} finally {
    Pop-Location
}

if ($Serve) {
    python -m http.server 8080 --directory "$root/rust/target/web"
}
