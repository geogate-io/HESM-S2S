cmake_minimum_required(VERSION 3.19)
project(mom6 LANGUAGES Fortran)

# GNU Compiler options
set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -g -fbacktrace")
set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -fdefault-real-8 -fdefault-double-8")
set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -Waliasing -fcray-pointer -fconvert=big-endian -ffree-line-length-none -fno-range-check -fbacktrace")
set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -I/glade/work/epicufsrt/contrib/spack-stack/derecho/spack-stack-1.9.2/envs/ue-gcc-12.2.0/install/gcc/12.2.0/fms-2024.02-k6pfcd2/include_r8")
set(CMAKE_Fortran_FLAGS_RELEASE "-O2")
list(APPEND MOM6_SHARE_DEFS "CPRGNU")

include("mom6_files.cmake")
list(APPEND CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/cmake)

# Find NetCDF
if(NOT NetCDF_FOUND)
  find_package(NetCDF REQUIRED C Fortran)
endif()

# Find ESMF
if(NOT ESMF_FOUND)
  find_package(ESMF 8.6.0 REQUIRED)
endif()

# Core model
add_library(mom6_obj OBJECT ${mom6_src_files})
set_target_properties(mom6_obj PROPERTIES Fortran_MODULE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/mod)
target_include_directories(mom6_obj PUBLIC $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}/mod>)
target_include_directories(mom6_obj PUBLIC $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/MOM6/config_src/memory/dynamic_nonsymmetric>)
target_include_directories(mom6_obj PUBLIC $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/MOM6/src/framework>)
target_include_directories(mom6_obj PRIVATE ${NetCDF_Fortran_INCLUDE_DIRS})
target_link_libraries(mom6_obj PUBLIC fms_r8 esmf stochastic_physics NetCDF::NetCDF_Fortran)

# NUOPC cap
add_library(mom6_nuopc_obj OBJECT ${mom6_nuopc_src_files})
set_target_properties(mom6_nuopc_obj PROPERTIES Fortran_MODULE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/mod)
target_include_directories(mom6_nuopc_obj PUBLIC $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}/mod>)
target_include_directories(mom6_nuopc_obj PUBLIC $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/MOM6/config_src/memory/dynamic_nonsymmetric>)
target_include_directories(mom6_nuopc_obj PUBLIC $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/shared>)
target_compile_definitions(mom6_nuopc_obj PRIVATE ${MOM6_SHARE_DEFS})
target_include_directories(mom6_nuopc_obj PRIVATE ${ESMF_F90COMPILEPATHS})
target_link_libraries(mom6_nuopc_obj PUBLIC mom6_obj fms_r8 esmf stochastic_physics)

# Create dummy source to prevent No SOURCES given to target error
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/mom6_dummy.F90" "subroutine mom6_dummy()\nend subroutine mom6_dummy\n")
set(mom6_src_files "${CMAKE_CURRENT_BINARY_DIR}/mom6_dummy.F90")

# Define static library that has model and NUOPC cap
add_library(mom6 STATIC ${mom6_src_files})
target_link_libraries(mom6 PRIVATE mom6_obj mom6_nuopc_obj)
target_include_directories(mom6 PUBLIC $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}/mod>)

# Export/Install targets
install(
  TARGETS mom6 mom6_obj mom6_nuopc_obj
  EXPORT  mom6-config
  RUNTIME DESTINATION bin
  LIBRARY DESTINATION lib
  ARCHIVE DESTINATION lib
  COMPONENT Library
)

install(DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/mod DESTINATION ${CMAKE_INSTALL_PREFIX})

install(
  EXPORT mom6-config
  DESTINATION lib/cmake
)
