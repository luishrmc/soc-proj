import xsdb
import sys

s = xsdb.start_debug_session()
s.connect()
s.targets(2)
s.configparams("force-mem-accesses", "1")

base = 0x41E00000
print("--- SPICR (0x41E00060) ---")
s.mrd(base + 0x60, 1)
print("--- SPISR (0x41E00064) ---")
s.mrd(base + 0x64, 1)
print("--- RX_FIFO_OCY (0x41E00078) ---")
s.mrd(base + 0x78, 1)
