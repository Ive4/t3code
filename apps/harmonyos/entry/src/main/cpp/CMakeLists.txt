cmake_minimum_required(VERSION 3.11)
project(t3code_harmonyos)

set(RNOH_APP_DIR "${CMAKE_CURRENT_SOURCE_DIR}")
set(RNOH_CPP_DIR "${RNOH_APP_DIR}/../../../../oh_modules/@rnoh/react-native-openharmony/include")
include("${RNOH_CPP_DIR}/react-native-harmony.cmake")

add_library(rnoh_app SHARED PackageProvider.cpp "${RNOH_CPP_DIR}/RNOHAppNapiBridge.cpp")
target_link_libraries(rnoh_app PUBLIC rnoh)
