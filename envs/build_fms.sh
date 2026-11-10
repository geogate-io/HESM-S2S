#!/bin/bash
# Build FMS 2024.02 from source and register it as an Lmod module, on any
# system with Lmod + a Fortran-capable MPI compiler wrapper (mpif90) --
# originally written for Casper, now parameterized via env vars so the
# same script also works on e.g. TACC Vista (its own module names are
# NOT known here -- set them yourself from `module avail`/`module
# spider` on that system; nothing below is a guess at Vista's values).
#
# Derecho gets FMS from epicufsrt's spack-stack-1.9.2 (module fms/2024.02,
# built for gcc/12.2.0 + cray-mpich/8.1.27). Systems without an equivalent
# module/spack-stack tree can't just reuse that install (it's tagged for
# Derecho's own "zen3" CPU target). This script reproduces that same
# spack build (same source, same patch, same CMake options -- see
# .spack/spack-configure-args.txt and the fms/package.py recipe recorded
# in the derecho install) as a plain CMake build against whatever
# compiler/MPI/netCDF modules are loaded.
#
# Env vars (all optional -- defaults reproduce the original Casper build
# exactly, so plain `./build_fms.sh` on Casper is unchanged):
#   INSTALL_ROOT   where to install/write the module (default: Casper's own)
#   PLATFORM_LABEL short tag recorded in the generated module's docstring
#   MODULE_NCARENV  NCAR's own base env module; set to "" to skip entirely
#                    (there is no NCAR ncarenv module outside NCAR systems)
#   MODULE_GCC, MODULE_MPI, MODULE_CMAKE, MODULE_HDF5, MODULE_NETCDF
#                    compiler/MPI/build-tool/IO-library modules to load;
#                    each may be set to "" to skip loading it (e.g. if
#                    already loaded by the calling environment)
#   BUILD_DIR_ROOT  scratch root for the build (default: Casper's own)
#
# Usage: ./build_fms.sh   (run on a login node or interactive session;
#                           the build itself is a few minutes, no GPU/
#                           queue needed)
set -euo pipefail

FMS_VERSION=2024.02
FMS_SHA256=47e5740bb066f5eb032e1de163eb762c7258880a2932f4cc4e34e769e0cc2b0e
FMS_PATCH_URL="https://github.com/NOAA-GFDL/fms/pull/1559.patch?full_index=1"
FMS_PATCH_SHA256=2b12a6c35f357c3dddcfa5282576e56ab0e8e6c1ad1dab92a2c85ce3dfb815d4

PLATFORM_LABEL=${PLATFORM_LABEL:-Casper}
INSTALL_ROOT=${INSTALL_ROOT:-/glade/work/turuncu/ML-2.0/envs/casper}
MODULE_NCARENV=${MODULE_NCARENV-ncarenv/25.10}
MODULE_GCC=${MODULE_GCC-gcc/14.3.0}
MODULE_MPI=${MODULE_MPI-openmpi/5.0.8}
MODULE_CMAKE=${MODULE_CMAKE-cmake/3.31.8}
MODULE_HDF5=${MODULE_HDF5-hdf5-mpi/1.14.6}
MODULE_NETCDF=${MODULE_NETCDF-netcdf-mpi/4.9.3}
BUILD_DIR_ROOT=${BUILD_DIR_ROOT:-/glade/derecho/scratch/$USER/casper_build}

PREFIX=${INSTALL_ROOT}/fms/${FMS_VERSION}
MODULEDIR=${INSTALL_ROOT}/modulefiles/fms
BUILD_DIR=${TMPDIR:-${BUILD_DIR_ROOT}}/fms-${FMS_VERSION}

module --force purge
[ -n "${MODULE_NCARENV}" ] && module load "${MODULE_NCARENV}"
[ -n "${MODULE_GCC}" ] && module load "${MODULE_GCC}"
[ -n "${MODULE_MPI}" ] && module load "${MODULE_MPI}"
[ -n "${MODULE_CMAKE}" ] && module load "${MODULE_CMAKE}"
[ -n "${MODULE_HDF5}" ] && module load "${MODULE_HDF5}"
[ -n "${MODULE_NETCDF}" ] && module load "${MODULE_NETCDF}"

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

curl -sL "https://github.com/NOAA-GFDL/FMS/archive/refs/tags/${FMS_VERSION}.tar.gz" -o fms.tar.gz
echo "${FMS_SHA256}  fms.tar.gz" | sha256sum -c -
tar xzf fms.tar.gz
cd "FMS-${FMS_VERSION}"

curl -sL "${FMS_PATCH_URL}" -o fms-1559.patch
echo "${FMS_PATCH_SHA256}  fms-1559.patch" | sha256sum -c -
patch -p1 < fms-1559.patch

cmake -S . -B build \
  -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER=mpicc \
  -DCMAKE_Fortran_COMPILER=mpif90 \
  -DGFS_PHYS:BOOL=ON \
  -DOPENMP:BOOL=ON \
  -DENABLE_QUAD_PRECISION:BOOL=ON \
  -DSHARED_LIBS:BOOL=OFF \
  -DWITH_YAML:BOOL=OFF \
  -DCONSTANTS:STRING=GFS \
  -DLARGEFILE:BOOL=OFF \
  -DINTERNAL_FILE_NML:BOOL=ON \
  -D32BIT:BOOL=ON \
  -D64BIT:BOOL=ON \
  -DFPIC:BOOL=ON \
  -DUSE_DEPRECATED_IO:BOOL=ON

cmake --build build -j8
cmake --install build

mkdir -p "${MODULEDIR}"
cat > "${MODULEDIR}/${FMS_VERSION}.lua" <<EOF
-- -*- lua -*-
-- FMS ${FMS_VERSION}, built for ${PLATFORM_LABEL} (${MODULE_GCC:-no gcc module}, ${MODULE_MPI:-no MPI module})
-- Mirrors the derecho spack-stack fms/${FMS_VERSION} module (setenv fms_ROOT
-- + CMAKE_PREFIX_PATH/LD_LIBRARY_PATH) that build.sh expects.

whatis("Name : fms")
whatis("Version : ${FMS_VERSION}")
whatis("Short description : GFDL Flexible Modeling System, built for ${PLATFORM_LABEL}")

$( [ -n "${MODULE_GCC}" ] && echo "depends_on(\"${MODULE_GCC}\")" )
$( [ -n "${MODULE_MPI}" ] && echo "depends_on(\"${MODULE_MPI}\")" )
$( [ -n "${MODULE_NETCDF}" ] && echo "depends_on(\"${MODULE_NETCDF}\")" )

prepend_path("LD_LIBRARY_PATH", "${PREFIX}/lib")
prepend_path("CMAKE_PREFIX_PATH", "${PREFIX}")
setenv("fms_ROOT", "${PREFIX}")
EOF

echo "FMS ${FMS_VERSION} installed to ${PREFIX}"
echo "Module written to ${MODULEDIR}/${FMS_VERSION}.lua"
echo "Add to your env_gnu.sh: module use -a ${INSTALL_ROOT}/modulefiles && module load fms/${FMS_VERSION}"
