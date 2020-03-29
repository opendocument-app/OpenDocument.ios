cmake_minimum_required(VERSION 3.12.4)

option (ODR_TEST "" OFF)
set(ODR_TEST OFF)

# set both to ON for simulator builds, off for devices
option(DISABLE_ASM "" OFF)
set(DISABLE_ASM OFF)

add_subdirectory(OpenDocument.core)
