cmake_minimum_required(VERSION 3.11)
project(t3code_harmonyos)

set(RNOH_APP_DIR "${CMAKE_CURRENT_SOURCE_DIR}")
set(RNOH_CPP_DIR "${RNOH_APP_DIR}/../../../../oh_modules/@rnoh/react-native-openharmony/src/main/cpp")
set_property(GLOBAL PROPERTY JOB_POOLS t3_compile=4 t3_link=1)
set(CMAKE_JOB_POOL_COMPILE t3_compile)
set(CMAKE_JOB_POOL_LINK t3_link)
set(CMAKE_OBJECT_PATH_MAX 160)
set(ENABLE_COMPILE_OPTIMIZATIONS OFF)
add_subdirectory("${RNOH_CPP_DIR}" ./rn)

add_library(rnoh_app SHARED PackageProvider.cpp "${RNOH_CPP_DIR}/RNOHAppNapiBridge.cpp")
add_subdirectory("${RNOH_APP_DIR}/../../../../gesture/src/main/cpp" ./gesture)
add_subdirectory("${RNOH_APP_DIR}/../../../../worklets/src/main/cpp" ./worklets)
add_subdirectory("${RNOH_APP_DIR}/../../../../reanimated/src/main/cpp" ./reanimated)
add_subdirectory("${RNOH_APP_DIR}/../../../../safe_area/src/main/cpp" ./safe_area)
add_subdirectory("${RNOH_APP_DIR}/../../../../svg/src/main/cpp" ./svg)
add_subdirectory("${RNOH_APP_DIR}/../../../../screens/src/main/cpp" ./screens)
add_subdirectory("${RNOH_APP_DIR}/../../../../keyboard/src/main/cpp" ./keyboard)
target_link_libraries(rnoh_app PUBLIC
  rnoh_keyboard_controller
  rnoh_screens
  rnoh_svg
  rnoh_safe_area
  rnoh
  rnoh_gesture_handler
  rnoh_worklets
  rnoh_reanimated
)
