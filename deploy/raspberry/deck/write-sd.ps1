# Scrive l'immagine del Deck su una scheda SD e la rilegge per verificarla.
# Va eseguito come amministratore. Cancella TUTTO il disco indicato: accetta solo dischi USB/SD
# rimovibili fino a 64 GB, diversi dal disco di sistema.
#
#   .\write-sd.ps1 -Image deck.img -Disk 2              (il numero del disco: Get-Disk)
#   .\write-sd.ps1 -Image deck.img -Disk 2 -Yes         (senza chiedere conferma)
#   .\write-sd.ps1 -Image deck.img -Disk 2 -VerifyOnly  (solo il confronto, senza scrivere)
#   .\write-sd.ps1 -Image deck.img -Disk 2 -Secret ..\..\..\secret\pi2img
#       dopo la scrittura copia wifi.txt e ssh.txt di quella cartella (privata, fuori da git) in
#       secret\ della partizione di boot
#
# Appena vede la tabella delle partizioni Windows monta la partizione FAT, ci scrive la cartella
# "System Volume Information" (che al Raspberry non dà fastidio) e da lì in poi rifiuta la
# scrittura diretta dei settori dei volumi montati. Per questo il primo blocco, con la tabella,
# si scrive per ultimo e tutto il resto si verifica prima di scriverlo.
param(
    [Parameter(Mandatory)][string]$Image,
    [Parameter(Mandatory)][int]$Disk,
    [switch]$Yes,
    [switch]$VerifyOnly,
    [string]$Secret,
    [string]$Log
)
$ErrorActionPreference = 'Stop'
if ($Log) { Start-Transcript -Path $Log | Out-Null }
$chunk = 4MB

# Blocchi di $chunk byte diversi tra immagine e disco, da $from a $to: i loro scostamenti
function Compare-Range($src, $dst, [long]$from, [long]$to, [string]$what) {
    $a = New-Object byte[] $chunk
    $b = New-Object byte[] $chunk
    $bad = New-Object System.Collections.Generic.List[long]
    $md5 = [Security.Cryptography.MD5]::Create()
    $src.Position = $from
    $dst.Position = $from
    $pos = $from
    while ($pos -lt $to) {
        $want = [int][math]::Min([long]$chunk, [long]($to - $pos))
        $na = 0; while ($na -lt $want) { $na += $src.Read($a, $na, $want - $na) }
        $nb = 0; while ($nb -lt $want) { $nb += $dst.Read($b, $nb, $want - $nb) }
        $ha = [BitConverter]::ToString($md5.ComputeHash($a, 0, $want))
        $hb = [BitConverter]::ToString($md5.ComputeHash($b, 0, $want))
        if ($ha -ne $hb) { $bad.Add($pos) }
        $pos += $want
        Write-Progress -Activity "Verifica $what" -PercentComplete (100 * ($pos - $from) / [math]::Max([long]1, [long]($to - $from)))
    }
    return , $bad
}

try {
    $img = Get-Item -LiteralPath $Image
    $d = Get-Disk -Number $Disk
    if ($d.BusType -notin @('USB', 'SD', 'MMC')) { throw "il disco $Disk è $($d.BusType), non una scheda SD" }
    if ($d.IsBoot -or $d.IsSystem) { throw "il disco $Disk è il disco di sistema" }
    if ($d.Size -gt 64GB) { throw "il disco $Disk è di $([math]::Round($d.Size / 1GB)) GB: troppo grande per una SD del Deck" }
    if ($img.Length -gt $d.Size) { throw "l'immagine ($($img.Length) byte) non entra nel disco ($($d.Size) byte)" }
    if ($img.Length % 512) { throw "la lunghezza dell'immagine non è un multiplo di 512" }

    Write-Host "Disco $Disk`: $($d.FriendlyName), $([math]::Round($d.Size / 1GB, 1)) GB, $($d.BusType)"
    Get-Partition -DiskNumber $Disk -ErrorAction SilentlyContinue |
        ForEach-Object { Write-Host "  partizione $($_.PartitionNumber) $($_.DriveLetter) $([math]::Round($_.Size / 1MB)) MB da $([math]::Round($_.Offset / 1MB)) MB" }

    $src = [IO.File]::OpenRead($img.FullName)
    $first = [int][math]::Min([long]$chunk, [long]$img.Length)
    if ($VerifyOnly) {
        $dst = New-Object IO.FileStream("\\.\PhysicalDrive$Disk", [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite, $chunk)
        try {
            $bad = Compare-Range $src $dst 0 $img.Length "di tutto il disco"
        } finally { $dst.Dispose(); $src.Dispose() }
        if ($bad.Count -eq 0) { Write-Host "identica all'immagine" }
        foreach ($o in $bad) { Write-Host ("diverso il blocco da {0} MB" -f ($o / 1MB)) }
        Write-Host "FATTO ($($bad.Count) blocchi diversi)"
        exit 0
    }

    if (-not $Yes) {
        if ((Read-Host "Cancellare il disco $Disk e scriverci $($img.Name)? (si/no)") -ne 'si') { throw "annullato" }
    }
    # senza partizioni Windows non tiene volumi montati sul disco
    Clear-Disk -Number $Disk -RemoveData -RemoveOEM -Confirm:$false

    $buf = New-Object byte[] $chunk
    $dst = New-Object IO.FileStream("\\.\PhysicalDrive$Disk", [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite,
        [IO.FileShare]::ReadWrite, $chunk, [IO.FileOptions]::WriteThrough)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        # 1. primo blocco azzerato: nessuna partizione visibile durante la scrittura
        $dst.Write((New-Object byte[] $first), 0, $first)
        $dst.Flush()
        # 2. tutto il resto
        $src.Position = $first
        $done = [long]$first
        while (($n = $src.Read($buf, 0, $chunk)) -gt 0) {
            $dst.Write($buf, 0, $n)
            $done += $n
            Write-Progress -Activity "Scrittura" -Status "$([math]::Round($done / 1MB)) / $([math]::Round($img.Length / 1MB)) MB" -PercentComplete (100 * $done / $img.Length)
        }
        $dst.Flush()
        Write-Host "scritti $([math]::Round($done / 1MB)) MB in $([math]::Round($sw.Elapsed.TotalSeconds)) s"
        # 3. verifica del resto, finché Windows non vede ancora le partizioni
        $bad = Compare-Range $src $dst $first $img.Length "dei dati"
        if ($bad.Count) { throw "verifica fallita: $($bad.Count) blocchi diversi, il primo da $($bad[0] / 1MB) MB" }
        # 4. per ultimo il primo blocco, con la tabella delle partizioni, e la sua verifica
        $src.Position = 0
        [void]$src.Read($buf, 0, $first)
        $dst.Position = 0
        $dst.Write($buf, 0, $first)
        $dst.Flush()
        $bad = Compare-Range $src $dst 0 $first "della tabella delle partizioni"
        if ($bad.Count) { throw "verifica fallita nella tabella delle partizioni" }
        Write-Host "verifica riuscita"
    } finally {
        $dst.Dispose()
        $src.Dispose()
    }
    Update-Disk -Number $Disk
    if ($Secret) {
        # la partizione di boot compare come unità di Windows qualche istante dopo la scrittura
        $letter = $null
        for ($i = 0; $i -lt 30 -and -not $letter; $i++) {
            $letter = (Get-Partition -DiskNumber $Disk -PartitionNumber 1 -ErrorAction SilentlyContinue).DriveLetter
            if (-not $letter) { Start-Sleep 1 }
        }
        if (-not $letter) { throw "la partizione di boot non ha una lettera di unità: copiare a mano $Secret" }
        $dest = "$($letter):\secret"
        New-Item -ItemType Directory -Force $dest | Out-Null
        foreach ($f in 'wifi.txt', 'ssh.txt') {
            if (Test-Path (Join-Path $Secret $f)) { Copy-Item (Join-Path $Secret $f) $dest -Force; Write-Host "copiato $f in $dest" }
        }
    }
    Write-Host "FATTO"
} catch {
    Write-Host "ERRORE: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    if ($Log) { Stop-Transcript | Out-Null }
}
