/**
 * @file axi_io.h
 * @brief Memory-Mapped I/O and Cache Coherency Abstraction for AXI Drivers.
 *
 * Provides direct zero-overhead hardware mapping on ARM Cortex-A9 (Xilinx BSP)
 * and mock hook bindings for host unit testing with 100% test coverage.
 */

#ifndef AXI_IO_H
#define AXI_IO_H

#include <stdint.h>
#include <stddef.h>

#if defined(__arm__) || defined(__aarch64__)
#include "xil_io.h"
#include "xil_cache.h"

#define AXI_IO_READ32(addr)          Xil_In32((uintptr_t)(addr))
#define AXI_IO_WRITE32(addr, val)    Xil_Out32((uintptr_t)(addr), (uint32_t)(val))
#define AXI_DCACHE_FLUSH(addr, sz)   Xil_DCacheFlushRange((intptr_t)(addr), (unsigned)(sz))
#define AXI_DCACHE_INVAL(addr, sz)   Xil_DCacheInvalidateRange((intptr_t)(addr), (unsigned)(sz))

#else

#ifdef __cplusplus
extern "C" {
#endif

/* Host Mock Hooks */
uint32_t host_mock_read32(uintptr_t addr);
void     host_mock_write32(uintptr_t addr, uint32_t val);

#ifdef __cplusplus
}
#endif

#define AXI_IO_READ32(addr)          host_mock_read32((uintptr_t)(addr))
#define AXI_IO_WRITE32(addr, val)    host_mock_write32((uintptr_t)(addr), (uint32_t)(val))
#define AXI_DCACHE_FLUSH(addr, sz)   ((void)(addr), (void)(sz))
#define AXI_DCACHE_INVAL(addr, sz)   ((void)(addr), (void)(sz))

#endif

#endif /* AXI_IO_H */
