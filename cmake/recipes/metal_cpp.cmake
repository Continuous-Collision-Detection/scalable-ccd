# metal-cpp-cmake (https://github.com/LeeTeng2001/metal-cpp-cmake.git)
# License: Apache 2.0
if(TARGET metal_cpp::metal_cpp)
    return()
endif()

message(STATUS "Third-party: creating target 'metal_cpp::metal_cpp'")

set(METAL_CPP_BUILD_TESTS OFF CACHE BOOL "Build examples" FORCE)

include(CPM)
CPMAddPackage("gh:LeeTeng2001/metal-cpp-cmake#4c7f808c111fcedea38c1fc103978d90a8750acd")

add_library(metal_cpp::metal_cpp ALIAS METAL_CPP)