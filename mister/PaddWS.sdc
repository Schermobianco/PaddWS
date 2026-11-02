# I clock della PLL del core: clk_sys (20 MHz) e clk_cpu (60 MHz, processore di rtl/pong_logic_rv.v),
# dallo stesso VCO e quindi correlati. Nessuna eccezione per i passaggi tra i due: sono tutti da
# registro a registro e Quartus li analizza con la relazione vera tra i fronti (al peggio 16,7 ns).
derive_pll_clocks
derive_clock_uncertainty

# core specific constraints
