# VexRiscv

Processore RISC-V a 32 bit (RV32IM) di [SpinalHDL/VexRiscv](https://github.com/SpinalHDL/VexRiscv),
licenza MIT ([LICENSE](LICENSE), Copyright (c) 2016 Spinal HDL contributors). Esegue il firmware
`rust/mister-fw` in `rtl/pong_logic_rv.v`.

`VexRiscv.v` è il file già generato della variante *standard* di LiteX, copiato senza modifiche dal
pacchetto [litex-hub/pythondata-cpu-vexriscv](https://github.com/litex-hub/pythondata-cpu-vexriscv)
(`pythondata_cpu_vexriscv/verilog/VexRiscv.v`, commit `642ecfed1c84460555d6d803d660cc60cfc1ecb6`,
SHA-256 `e74ce169faabde98b851881527b055d1ee940995c4693838fcb232df0856510b`). L'intestazione del file
indica SpinalHDL v1.9.4 e VexRiscv `63430af99f84cc1d11d58b556debe1cc3f238c67`; il Makefile del
pacchetto lo genera con `sbt "runMain vexriscv.GenCoreDefault"` (opzioni predefinite):

- RV32IM, pipeline a 5 stadi con bypass, previsione statica dei salti;
- cache istruzioni da 4 KB e cache dati da 4 KB (write-through), righe da 32 byte, una via;
- moltiplicazione in un ciclo (DSP), divisione iterativa, shift in un ciclo;
- CSR ridotti, interruzioni non usate (ingressi a zero), vettore di reset da ingresso (0);
- bus Wishbone per istruzioni e dati; gli indirizzi con il bit 31 a uno sono I/O (senza cache).

Per rigenerarlo servirebbero Scala e SpinalHDL: il progetto non li usa.
