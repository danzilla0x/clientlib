include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(clientlib_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(clientlib_setup_options)
  option(clientlib_ENABLE_HARDENING "Enable hardening" ON)
  option(clientlib_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    clientlib_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    clientlib_ENABLE_HARDENING
    OFF)

  clientlib_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR clientlib_PACKAGING_MAINTAINER_MODE)
    option(clientlib_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(clientlib_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(clientlib_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(clientlib_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(clientlib_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(clientlib_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(clientlib_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(clientlib_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(clientlib_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(clientlib_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(clientlib_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(clientlib_ENABLE_PCH "Enable precompiled headers" OFF)
    option(clientlib_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(clientlib_ENABLE_IPO "Enable IPO/LTO" ON)
    option(clientlib_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(clientlib_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(clientlib_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(clientlib_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(clientlib_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(clientlib_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(clientlib_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(clientlib_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(clientlib_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(clientlib_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(clientlib_ENABLE_PCH "Enable precompiled headers" OFF)
    option(clientlib_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      clientlib_ENABLE_IPO
      clientlib_WARNINGS_AS_ERRORS
      clientlib_ENABLE_USER_LINKER
      clientlib_ENABLE_SANITIZER_ADDRESS
      clientlib_ENABLE_SANITIZER_LEAK
      clientlib_ENABLE_SANITIZER_UNDEFINED
      clientlib_ENABLE_SANITIZER_THREAD
      clientlib_ENABLE_SANITIZER_MEMORY
      clientlib_ENABLE_UNITY_BUILD
      clientlib_ENABLE_CLANG_TIDY
      clientlib_ENABLE_CPPCHECK
      clientlib_ENABLE_COVERAGE
      clientlib_ENABLE_PCH
      clientlib_ENABLE_CACHE)
  endif()

  clientlib_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (clientlib_ENABLE_SANITIZER_ADDRESS OR clientlib_ENABLE_SANITIZER_THREAD OR clientlib_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(clientlib_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(clientlib_global_options)
  if(clientlib_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    clientlib_enable_ipo()
  endif()

  clientlib_supports_sanitizers()

  if(clientlib_ENABLE_HARDENING AND clientlib_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR clientlib_ENABLE_SANITIZER_UNDEFINED
       OR clientlib_ENABLE_SANITIZER_ADDRESS
       OR clientlib_ENABLE_SANITIZER_THREAD
       OR clientlib_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${clientlib_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${clientlib_ENABLE_SANITIZER_UNDEFINED}")
    clientlib_enable_hardening(clientlib_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(clientlib_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(clientlib_warnings INTERFACE)
  add_library(clientlib_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  clientlib_set_project_warnings(
    clientlib_warnings
    ${clientlib_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(clientlib_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    configure_linker(clientlib_options)
  endif()

  include(cmake/Sanitizers.cmake)
  clientlib_enable_sanitizers(
    clientlib_options
    ${clientlib_ENABLE_SANITIZER_ADDRESS}
    ${clientlib_ENABLE_SANITIZER_LEAK}
    ${clientlib_ENABLE_SANITIZER_UNDEFINED}
    ${clientlib_ENABLE_SANITIZER_THREAD}
    ${clientlib_ENABLE_SANITIZER_MEMORY})

  set_target_properties(clientlib_options PROPERTIES UNITY_BUILD ${clientlib_ENABLE_UNITY_BUILD})

  if(clientlib_ENABLE_PCH)
    target_precompile_headers(
      clientlib_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(clientlib_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    clientlib_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(clientlib_ENABLE_CLANG_TIDY)
    clientlib_enable_clang_tidy(clientlib_options ${clientlib_WARNINGS_AS_ERRORS})
  endif()

  if(clientlib_ENABLE_CPPCHECK)
    clientlib_enable_cppcheck(${clientlib_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(clientlib_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    clientlib_enable_coverage(clientlib_options)
  endif()

  if(clientlib_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(clientlib_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(clientlib_ENABLE_HARDENING AND NOT clientlib_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR clientlib_ENABLE_SANITIZER_UNDEFINED
       OR clientlib_ENABLE_SANITIZER_ADDRESS
       OR clientlib_ENABLE_SANITIZER_THREAD
       OR clientlib_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    clientlib_enable_hardening(clientlib_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
