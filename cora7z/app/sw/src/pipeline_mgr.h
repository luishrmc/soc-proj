/**
 * @file pipeline_mgr.h
 * @brief Heterogeneous PS/PL Compress-then-Encrypt (LZSS + AES-128-CTR) Pipeline Manager.
 *
 * Provides a unified bare-metal driver interface for both pure-software baseline
 * and dual-port BRAM hardware offload engines on the Xilinx Zynq-7000 SoC.
 *
 * Supported Scenarios:
 *   Case 1: Pure Software (SW LZSS -> SW AES-128-CTR)
 *   Case 2: Compression Offload (PL LZSS -> SW AES-128-CTR)
 *   Case 3: Encryption Offload (SW LZSS -> PL AES-128-CTR)
 *   Case 4: Full Hardware Acceleration (PL LZSS -> PL AES-128-CTR)
 */

#ifndef PIPELINE_MGR_H
#define PIPELINE_MGR_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ========================================================================= */
/* Status and Error Codes                                                    */
/* ========================================================================= */
#define PIPELINE_SUCCESS              0
#define PIPELINE_ERR_PARAM           -1
#define PIPELINE_ERR_COMPRESSION     -2
#define PIPELINE_ERR_ENCRYPTION      -3
#define PIPELINE_ERR_OVERFLOW        -4
#define PIPELINE_ERR_PL_NOT_READY    -5
#define PIPELINE_ERR_LZSS_TIMEOUT    -6
#define PIPELINE_ERR_AES_TIMEOUT     -7
#define PIPELINE_ERR_VERIFY_MISMATCH -8

/* Maximum Supported Frame and BRAM Buffer Size (bytes) */
#define PIPELINE_MAX_FRAME_SIZE      2048U
#define ACCEL_BRAM_CAPACITY_BYTES    2048U

#ifndef AES_CTR_BLOCK_SIZE
#define AES_CTR_BLOCK_SIZE           16U
#endif

/* ========================================================================= */
/* Hardware Address Map Definitions (ADR-012, ADR-017)                       */
/* ========================================================================= */

/* Abstract Accelerator Base Addresses */
#define LZSS_ACCEL_BASE_ADDR         0x40000000U
#define AES_ACCEL_BASE_ADDR          0x40010000U

/* Sub-range BRAM Offsets relative to Accel Base Addresses */
#define ACCEL_BRAM_IN_OFFSET         0x0000U
#define ACCEL_BRAM_OUT_OFFSET        0x2000U

/* Physical BRAM Base Addresses (Port A AXI BRAM Controllers) */
#ifdef XPAR_AXI_BRAM_CTRL_LZSS_IN_BASEADDR
  #define LZSS_BRAM_IN_BASEADDR      XPAR_AXI_BRAM_CTRL_LZSS_IN_BASEADDR
#else
  #define LZSS_BRAM_IN_BASEADDR      0x40000000U
#endif

#ifdef XPAR_AXI_BRAM_CTRL_LZSS_OUT_BASEADDR
  #define LZSS_BRAM_OUT_BASEADDR     XPAR_AXI_BRAM_CTRL_LZSS_OUT_BASEADDR
#else
  #define LZSS_BRAM_OUT_BASEADDR     0x40002000U
#endif

#ifdef XPAR_AXI_BRAM_CTRL_AES_IN_BASEADDR
  #define AES_BRAM_IN_BASEADDR       XPAR_AXI_BRAM_CTRL_AES_IN_BASEADDR
#else
  #define AES_BRAM_IN_BASEADDR       0x40010000U
#endif

#ifdef XPAR_AXI_BRAM_CTRL_AES_OUT_BASEADDR
  #define AES_BRAM_OUT_BASEADDR      XPAR_AXI_BRAM_CTRL_AES_OUT_BASEADDR
#else
  #define AES_BRAM_OUT_BASEADDR      0x40012000U
#endif

/* Physical Accelerator CSR Base Addresses (AXI4-Lite Slaves) */
#ifdef XPAR_LZSS_ACCEL_0_BASEADDR
  #define LZSS_CSR_BASEADDR          XPAR_LZSS_ACCEL_0_BASEADDR
#else
  #define LZSS_CSR_BASEADDR          0x43C00000U
#endif

#ifdef XPAR_AES_ACCEL_0_BASEADDR
  #define AES_CSR_BASEADDR           XPAR_AES_ACCEL_0_BASEADDR
#else
  #define AES_CSR_BASEADDR           0x43C10000U
#endif

/* ========================================================================= */
/* Register Offsets and Bitfield Definitions                                 */
/* ========================================================================= */

/* Standard Control & Status Register Offsets (32-bit aligned) */
#define ACCEL_REG_CTRL               0x00U  /* Control Register (RW) */
#define ACCEL_REG_STATUS             0x04U  /* Status Register (RO) */
#define ACCEL_REG_INPUT_LEN          0x08U  /* Input Payload Length in bytes (RW) */
#define ACCEL_REG_OUTPUT_LEN         0x0CU  /* Output Payload Length in bytes (RO) */
#define ACCEL_REG_CYCLES             0x10U  /* Hardware Cycle Counter (RO) */

/* AES-128-CTR Specific Key & Nonce/Counter Register Offsets */
#define AES_REG_KEY0                 0x14U  /* Key Bytes [0..3] (RW) */
#define AES_REG_KEY1                 0x18U  /* Key Bytes [4..7] (RW) */
#define AES_REG_KEY2                 0x1CU  /* Key Bytes [8..11] (RW) */
#define AES_REG_KEY3                 0x20U  /* Key Bytes [12..15] (RW) */
#define AES_REG_IV0                  0x24U  /* IV Bytes [0..3] (RW) */
#define AES_REG_IV1                  0x28U  /* IV Bytes [4..7] (RW) */
#define AES_REG_IV2                  0x2CU  /* IV Bytes [8..11] (RW) */
#define AES_REG_CTR_INIT             0x30U  /* Initial 32-bit Counter Value (RW) */

/* Control Register Bitmasks (ACCEL_REG_CTRL @ 0x00) */
#define ACCEL_CTRL_START             (1U << 0)  /* Pulse: Trigger core execution */
#define ACCEL_CTRL_RESET             (1U << 1)  /* Pulse: Synchronous soft reset */
#define ACCEL_CTRL_IRQ_EN            (1U << 2)  /* Level: Hardware interrupt enable */

/* Status Register Bitmasks (ACCEL_REG_STATUS @ 0x04) */
#define ACCEL_STATUS_BUSY            (1U << 0)  /* Core FSM is actively processing */
#define ACCEL_STATUS_DONE            (1U << 1)  /* Core execution completed */
#define ACCEL_STATUS_ERROR           (1U << 2)  /* Processing or framing error */

/* Core Watchdog Polling Limit (iterations) */
#define ACCEL_WATCHDOG_MAX_ITERS     1200000U

/* ========================================================================= */
/* Pipeline Execution Scenarios & Metrics                                    */
/* ========================================================================= */

/**
 * @brief Pipeline Execution Scenarios for PS/PL Heterogeneous Benchmark.
 */
typedef enum {
    PIPELINE_SCENARIO_SW_SW = 0,  /* Case 1: Pure Software (SW LZSS -> SW AES) */
    PIPELINE_SCENARIO_HW_SW = 1,  /* Case 2: Compression Offload (HW LZSS -> SW AES) */
    PIPELINE_SCENARIO_SW_HW = 2,  /* Case 3: Encryption Offload (SW LZSS -> HW AES) */
    PIPELINE_SCENARIO_HW_HW = 3   /* Case 4: Full Hardware Acceleration (HW LZSS -> HW AES) */
} pipeline_scenario_t;

/**
 * @brief Performance and telemetry metrics structure.
 */
typedef struct {
    uint32_t            raw_len;           /* Original uncompressed payload length (bytes) */
    uint32_t            comp_len;          /* LZSS compressed length (bytes) */
    uint32_t            crypt_len;         /* AES-128-CTR ciphertext length (bytes) */
    uint32_t            comp_cycles;       /* Cortex-A9 PMU cycles consumed by compression */
    uint32_t            crypt_cycles;      /* Cortex-A9 PMU cycles consumed by encryption */
    uint32_t            total_cycles;      /* Total pipeline processing CPU cycles */
    uint32_t            comp_hw_cycles;    /* PL hardware cycle counter (100 MHz clock) */
    uint32_t            crypt_hw_cycles;   /* PL hardware cycle counter (100 MHz clock) */
    uint32_t            comp_time_us;      /* Elapsed compression time in microseconds */
    uint32_t            crypt_time_us;     /* Elapsed encryption time in microseconds */
    uint32_t            total_time_us;     /* Total elapsed pipeline time in microseconds */
    float               compression_ratio; /* CR = 1.0 - (comp_len / raw_len) */
    float               throughput_mbs;    /* Throughput in MB/s based on raw payload */
    pipeline_scenario_t scenario;          /* Executed pipeline scenario */
} pipeline_metrics_t;

/* ========================================================================= */
/* Driver Function Prototypes                                                */
/* ========================================================================= */

/**
 * @brief Initialize the pipeline manager and calibrate PMU/self-tests.
 * @return PIPELINE_SUCCESS (0) on success, negative error code on failure.
 */
int pipeline_init(void);

/**
 * @brief Generate a dynamic AES-128-CTR Initial Counter Block (IV) from sequence ID.
 *
 * Injects seq_id in Big-Endian into bytes 10-11 of the 96-bit nonce, with initial
 * counter 0x00000001 in bytes 12-15 per NIST SP 800-38A recommendations.
 *
 * @param[in]  seq_id 16-bit frame sequence counter.
 * @param[out] iv_out 16-byte buffer receiving initialized counter block.
 */
void pipeline_generate_frame_iv(uint16_t seq_id, uint8_t iv_out[AES_CTR_BLOCK_SIZE]);

/**
 * @brief Set the active frame sequence ID used for dynamic IV generation.
 * @param[in] seq_id Sequence identifier for the current frame.
 */
void pipeline_set_frame_seq_id(uint16_t seq_id);

/**
 * @brief Get the active frame sequence ID currently in use.
 * @return Current 16-bit sequence counter.
 */
uint16_t pipeline_get_frame_seq_id(void);

/**
 * @brief Check if Programmable Logic (PL) bitstream is loaded.
 * @return true if PCFG_DONE=1, false otherwise.
 */
bool pipeline_is_pl_ready(void);

/**
 * @brief Execute hardware LZSS compression offload over Dual-Port BRAM.
 *
 * Steps:
 *   1. Stage src into LZSS Input BRAM (32-bit burst write).
 *   2. Set REG_INPUT_LEN and pulse START in REG_CTRL.
 *   3. Poll REG_STATUS until DONE is asserted (watchdog protected).
 *   4. Read REG_OUTPUT_LEN, REG_CYCLES, and burst drain LZSS Output BRAM.
 *
 * @param[in]  src        Pointer to uncompressed input payload.
 * @param[in]  src_len    Length of input payload in bytes (1..2048).
 * @param[out] dst        Destination buffer for compressed output.
 * @param[in,out] dst_len Capacity of dst on entry, actual compressed bytes on exit.
 * @param[out] hw_cycles  Pointer receiving PL hardware execution cycle count.
 * @return PIPELINE_SUCCESS on success, negative error code on failure.
 */
int pipeline_lzss_hw_compress(const uint8_t *src,
                              size_t src_len,
                              uint8_t *dst,
                              size_t *dst_len,
                              uint32_t *hw_cycles);

/**
 * @brief Execute hardware AES-128-CTR encryption offload over Dual-Port BRAM.
 *
 * Steps:
 *   1. Program 128-bit Key, 96-bit Nonce, and 32-bit Counter registers.
 *   2. Stage src into AES Input BRAM (32-bit burst write).
 *   3. Set REG_INPUT_LEN and pulse START in REG_CTRL.
 *   4. Poll REG_STATUS until DONE is asserted (watchdog protected).
 *   5. Read REG_CYCLES and burst drain AES Output BRAM into dst.
 *
 * @param[in]  key       Pointer to 16-byte symmetric key.
 * @param[in]  iv        Pointer to 16-byte initial counter block (96-bit nonce + 32-bit ctr).
 * @param[in]  src       Pointer to plaintext input payload.
 * @param[in]  len       Length of payload in bytes (1..2048).
 * @param[out] dst       Destination buffer for ciphertext.
 * @param[out] hw_cycles Pointer receiving PL hardware execution cycle count.
 * @return PIPELINE_SUCCESS on success, negative error code on failure.
 */
int pipeline_aes_hw_crypt(const uint8_t *key,
                          const uint8_t *iv,
                          const uint8_t *src,
                          size_t len,
                          uint8_t *dst,
                          uint32_t *hw_cycles);

/**
 * @brief Execute Compress-then-Encrypt pipeline under a specific scenario.
 *
 * @param[in]  scenario   Execution scenario (SW_SW, HW_SW, SW_HW, HW_HW).
 * @param[in]  raw_in     Pointer to input raw telemetry buffer.
 * @param[in]  raw_len    Length of input payload in bytes.
 * @param[out] cipher_out Destination buffer for final ciphertext.
 * @param[in]  max_out_len Capacity of cipher_out buffer.
 * @param[out] final_len  Pointer receiving final ciphertext length in bytes.
 * @param[out] metrics    Pointer receiving stage cycle/time/ratio measurements.
 * @return PIPELINE_SUCCESS on success, negative error code on failure.
 */
int pipeline_process_frame_scenario(pipeline_scenario_t scenario,
                                    const uint8_t *raw_in,
                                    size_t raw_len,
                                    uint8_t *cipher_out,
                                    size_t max_out_len,
                                    size_t *final_len,
                                    pipeline_metrics_t *metrics);

/**
 * @brief Backward-compatible default frame processor.
 * Automatically selects Case 4 (Full Hardware Acceleration) if PL is ready,
 * or safely falls back to Case 1 (Pure Software Baseline) if fabric is unprogrammed.
 */
int pipeline_process_frame(const uint8_t *raw_in,
                           size_t raw_len,
                           uint8_t *cipher_out,
                           size_t max_out_len,
                           size_t *final_len,
                           pipeline_metrics_t *metrics);

/**
 * @brief Execute reverse pipeline (Decrypt-then-Decompress) for loopback verification.
 */
int pipeline_reverse_frame(const uint8_t *cipher_in,
                           size_t cipher_len,
                           uint8_t *raw_out,
                           size_t max_out_len,
                           size_t *recovered_len);

/**
 * @brief Verification unit test routine validating bit-exact parity across all 4 scenarios.
 *
 * Executes Scenarios 1, 2, 3, and 4 on raw_in, compares the generated ciphertexts
 * bit-by-bit against Case 1 (Pure Software), and verifies loopback recovery.
 *
 * @param[in] raw_in  Pointer to test payload.
 * @param[in] raw_len Length of test payload in bytes.
 * @return PIPELINE_SUCCESS on bit-exact match, PIPELINE_ERR_VERIFY_MISMATCH on failure.
 */
int pipeline_verify_all_scenarios(const uint8_t *raw_in, size_t raw_len);

#ifdef __cplusplus
}
#endif

#endif /* PIPELINE_MGR_H */
