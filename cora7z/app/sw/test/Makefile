CC      := gcc
CFLAGS  := -std=c11 -O2 -Wall -Wextra -Werror
SRC_DIR := ../src
BUILD   := build

INCS := -I$(SRC_DIR) \
        -I$(SRC_DIR)/comms \
        -I$(SRC_DIR)/compression \
        -I$(SRC_DIR)/crypto \
        -I$(SRC_DIR)/pipeline \
        -I$(SRC_DIR)/utils

SRCS := test_host_adr020.c \
        $(SRC_DIR)/comms/axi_spi_receiver.c \
        $(SRC_DIR)/compression/lzss_sw.c \
        $(SRC_DIR)/crypto/aes_ctr.c \
        $(SRC_DIR)/crypto/aes_ctr_sw.c \
        $(SRC_DIR)/pipeline/pipeline_mgr.c \
        $(SRC_DIR)/utils/telemetry_dataset.c \
        $(SRC_DIR)/utils/test_sw_pipeline.c

BIN := $(BUILD)/test_host_adr020

.PHONY: all run clean

all: $(BIN)

$(BIN): $(SRCS)
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) $(INCS) $(SRCS) -o $@

run: $(BIN)
	./$(BIN)

clean:
	rm -rf $(BUILD)
