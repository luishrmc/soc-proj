set(GENERATED_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated")
set(GENERATED_DATASET_H "${GENERATED_DIR}/telemetry_dataset.h")
set(GENERATED_DATASET_C "${GENERATED_DIR}/telemetry_dataset.c")

if(NOT CMAKE_BUILD_EARLY_EXPANSION)
    file(MAKE_DIRECTORY "${GENERATED_DIR}")
    idf_build_get_property(idf_python PYTHON)
    idf_build_get_property(sdkconfig_path SDKCONFIG)

    set(GENERATOR_SCRIPT "${CMAKE_CURRENT_SOURCE_DIR}/../scripts/generate_telemetry.py")
    set(PROFILES_SCRIPT "${CMAKE_CURRENT_SOURCE_DIR}/../scripts/telemetry_profiles.py")

    if(DEFINED CONFIG_ESP32_DATASET_SEED AND NOT "${CONFIG_ESP32_DATASET_SEED}" STREQUAL "")
        set(DATASET_SEED "${CONFIG_ESP32_DATASET_SEED}")
    else()
        set(DATASET_SEED 42)
    endif()

    if(DEFINED CONFIG_ESP32_DATASET_FRAMES_PER_PROFILE AND NOT "${CONFIG_ESP32_DATASET_FRAMES_PER_PROFILE}" STREQUAL "")
        set(DATASET_FRAMES_PER_PROFILE "${CONFIG_ESP32_DATASET_FRAMES_PER_PROFILE}")
    else()
        set(DATASET_FRAMES_PER_PROFILE 10)
    endif()

    set(GENERATOR_DEPS
        "${GENERATOR_SCRIPT}"
        "${PROFILES_SCRIPT}"
    )
    if(sdkconfig_path AND EXISTS "${sdkconfig_path}")
        list(APPEND GENERATOR_DEPS "${sdkconfig_path}")
    endif()

    add_custom_command(
        OUTPUT
            "${GENERATED_DATASET_H}"
            "${GENERATED_DATASET_C}"
        COMMAND "${CMAKE_COMMAND}" -E make_directory "${GENERATED_DIR}"
        COMMAND "${idf_python}" "${GENERATOR_SCRIPT}"
            --seed "${DATASET_SEED}"
            --frames-per-profile "${DATASET_FRAMES_PER_PROFILE}"
            --out-header "${GENERATED_DATASET_H}"
            --out-source "${GENERATED_DATASET_C}"
        DEPENDS
            ${GENERATOR_DEPS}
        COMMENT "Generating flash-resident Embedded Dataset (seed=${DATASET_SEED}, frames_per_profile=${DATASET_FRAMES_PER_PROFILE})"
        VERBATIM
    )

    set_source_files_properties("${GENERATED_DATASET_C}" PROPERTIES GENERATED TRUE)
endif()

idf_component_register(
    SRCS
        "main.c"
        "spi_injector_master.c"
        "trigger_gpio.c"
        "${GENERATED_DATASET_C}"
    INCLUDE_DIRS
        "."
        "${GENERATED_DIR}"
    REQUIRES
        esp_driver_spi
        esp_driver_gpio
        driver
        freertos
        esp_timer
        esp_system
        log
)

if(NOT CMAKE_BUILD_EARLY_EXPANSION)
    add_custom_target(generate_telemetry_dataset
        DEPENDS
            "${GENERATED_DATASET_H}"
            "${GENERATED_DATASET_C}"
    )
    add_dependencies(${COMPONENT_LIB} generate_telemetry_dataset)

    target_compile_options(${COMPONENT_LIB} PRIVATE -Wall -Wextra -Werror)
endif()
