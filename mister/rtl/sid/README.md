# SID

Emulazione del SID (MOS 6581 e 8580) presa dal core C64 del MiSTer:
<https://github.com/MiSTer-devel/C64_MiSTer>, cartella `rtl/sid`, ramo `master`, copiata il
2026-10-30.

- `sid_dac.sv` e `sid_filter.sv`: Copyright (C) 2022 Dag Lem e Alexey Melnikov, da reDIP-SID
  (<https://github.com/daglem/reDIP-SID>), licenza CERN-OHL-S v2: testo in
  [LICENSE-CERN-OHL-S-2.0.txt](LICENSE-CERN-OHL-S-2.0.txt) (<https://ohwr.org/cern_ohl_s_v2.txt>).
- `sid_top.sv`, `sid_voice.sv`, `sid_envelope.sv`, `sid_tables.sv`: dal core C64 del MiSTer
  (Alexey Melnikov e altri), senza intestazione di licenza.

Modifiche di PaddWS: attributo `multstyle = "logic"` su `sid_voice` e `sid_filter`, perché i
DSP del core sono tutti usati dalla logica di gioco; per Verilator, argomenti delle funzioni
dichiarati `input` invece di `wire` (`sid_filter.sv`, `sid_tables.sv`) e uscite delle tabelle
in `sid_top.sv` dichiarate `reg` invece di `wire` (sono assegnate in un blocco `always`). Il
resto è invariato.
