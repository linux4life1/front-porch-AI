cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "spell_check_plugin.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the application ID.
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

# Add dependency libraries. Add any application-specific dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)

# Asked before any audio player is built: audioplayers aborts the process
# when GStreamer's playbin is missing (issue #625). The audioplayers plugin
# links the same library, so this adds no new runtime requirement.
pkg_check_modules(GSTREAMER REQUIRED IMPORTED_TARGET gstreamer-1.0)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GSTREAMER)

# The spell check engine, compiled into this binary from third_party/hunspell.
# Not a system package and not dlopen'd: there is nothing for a user to install
# and nothing for a distribution to get wrong. See third_party/hunspell/
# README.fpai.md.
target_link_libraries(${BINARY_NAME} PRIVATE hunspell)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")
