# Costruisce la versione web (WebAssembly) in rust/target/web: paddws.wasm, la pagina
# (rust/web, con sid_audio.js per la musica del SID), le icone e il JavaScript di miniquad (nella
# versione di Cargo.lock) e di quad-snd (rust/vendor/quad-snd).
# Uso:  .\tools\build-web.ps1            poi, per provarla:  .\tools\build-web.ps1 -Serve
# (-Serve avvia un server locale su http://localhost:8080 con Python; dal telefono sulla stessa
# rete si apre http://<indirizzo del PC>:8080). Gira anche nella CI (pwsh su Linux).

param([switch]$Serve)

$ErrorActionPreference = "Continue"   # cargo scrive su stderr anche quando va tutto bene
$root = (Resolve-Path "$PSScriptRoot/..").Path
if (-not $env:CI) { . "$root/tools/rust-env.ps1" | Out-Null }   # in locale: toolchain portable
$cargoHome = if ($env:CARGO_HOME) { $env:CARGO_HOME } else { Join-Path $HOME ".cargo" }

Push-Location "$root/rust"
try {
    cargo build --release -p paddws --target wasm32-unknown-unknown
    if ($LASTEXITCODE -ne 0) { exit 1 }
    # il mq_js_bundle.js distribuito con macroquad 0.4.16 non parte: si compone dai sorgenti, gl.js
    # di miniquad nella versione di Cargo.lock e audio.js della nostra copia di quad-snd
    $lock = Get-Content Cargo.lock -Raw
    if ($lock -notmatch "name = `"miniquad`"\s+version = `"([^`"]+)`"") { throw "miniquad non trovato in Cargo.lock" }
    $gl = Get-ChildItem "$cargoHome/registry/src/*/miniquad-$($Matches[1])/js/gl.js" | Select-Object -First 1
    if (-not $gl) { throw "js/gl.js di miniquad $($Matches[1]) non trovato" }
    $js = @((Get-Content $gl.FullName -Raw), (Get-Content "$root/rust/vendor/quad-snd/js/audio.js" -Raw))

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
