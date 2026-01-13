cmake_minimum_required(VERSION 3.19)
project(cice6 LANGUAGES Fortran C)

# CICE GNU Fortran compiler flags
set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -g -fbacktrace")
set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -fconvert=big-endian -ffree-line-length-none ")
if(${CMAKE_Fortran_COMPILER_VERSION} VERSION_GREATER_EQUAL 10)
  set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -fallow-argument-mismatch -fallow-invalid-boz")
endif()
set(CMAKE_Fortran_FLAGS_RELEASE "-O2")
set(CMAKE_Fortran_FLAGS_DEBUG "-O0 -Wall -Wextra -fcheck=bounds -ffpe-trap=invalid,zero,overflow,underflow" )
set(CMAKE_Fortran_LINK_FLAGS "" )

# CICE GNU C compiler flags
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -g")
set(CMAKE_C_FLAGS_RELEASE "-O3")
set(CMAKE_C_FLAGS_DEBUG "-O0")
set(CMAKE_C_LINK_FLAGS "")

# Configuration Options
set(CICE_IO "PIO" CACHE STRING "CICE OPTIONS: Choose IO options.")
set_property(CACHE CICE_IO PROPERTY STRINGS "NetCDF" "PIO" "Binary")

# Too many files to list, so include them via this file
include("cice_files.cmake")

# Find required packages
list(APPEND CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/cmake)
if(NOT ESMF_FOUND)
  find_package(ESMF 8.6.0 REQUIRED)
endif()

# Special cases for compile time
set_source_files_properties(CICE/icepack/columnphysics/icepack_shortwave_data.F90 APPEND_STRING PROPERTY COMPILE_FLAGS " -O0")

# Collect source files for library
list(APPEND lib_src_files
  ${cice_shared_files}
  ${cice_shared_files_c}
  ${icepack_files}
  ${cice_mpi_comm_files}
  ${cice_nuopc_cmeps_driver_files})

# Add CPP definitions
list(APPEND _cice_defs
  FORTRANUNDERSCORE
  coupled)

# Select IO source files based on CICE_IO
if(CICE_IO MATCHES "NetCDF")
  list(APPEND lib_src_files ${cice_netcdf_io_files})
  list(APPEND _cice_defs USE_NETCDF)
elseif(CICE_IO MATCHES "PIO")
  list(APPEND lib_src_files ${cice_pio2_io_files})
  list(APPEND _cice_defs USE_NETCDF)
elseif(CICE_IO MATCHES "Binary")
  list(APPEND lib_src_files ${cice_binary_io_files})
endif()

# Create target library and set PUBLIC interfaces on the library
add_library(cice STATIC ${lib_src_files})
set_target_properties(cice PROPERTIES Fortran_MODULE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/mod)
target_compile_definitions(cice PUBLIC "${_cice_defs}")
target_include_directories(cice PUBLIC $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}/mod>
                                       $<INSTALL_INTERFACE:mod>)
target_include_directories(cice PRIVATE ${ESMF_F90COMPILEPATHS})
target_link_libraries(cice PUBLIC ESMF)
if(CICE_IO MATCHES "^(NetCDF|PIO)$")
  target_link_libraries(cice PUBLIC NetCDF)
  if(CICE_IO MATCHES "PIO")
    target_link_libraries(cice PUBLIC PIO)
  endif()
endif()

# Ice prescribed is depend on CDEPS
set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -I${CMAKE_CURRENT_BINARY_DIR}/../datm/share -I${CMAKE_CURRENT_BINARY_DIR}/../datm/dshr -I${CMAKE_CURRENT_BINARY_DIR}/../datm/streams")
target_link_libraries(cice PRIVATE ${CMAKE_CURRENT_BINARY_DIR}/../datm/dshr/libdshr.a ${CMAKE_CURRENT_BINARY_DIR}/../datm/share/libcdeps_share.a ${CMAKE_CURRENT_BINARY_DIR}/../datm/streams/libstreams.a)

###############################################################################
### Install
###############################################################################

install(
  TARGETS cice
  EXPORT  cice-config
  LIBRARY DESTINATION lib
  ARCHIVE DESTINATION lib
  COMPONENT Library)

install(DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/mod DESTINATION ${CMAKE_INSTALL_PREFIX})

install(EXPORT      cice-config
        DESTINATION lib/cmake)
