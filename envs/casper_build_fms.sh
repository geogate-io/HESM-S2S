#!/bin/bash
# Build FMS 2024.02 for Casper and register it as an Lmod module.
#
# Derecho gets FMS from epicufsrt's spack-stack-1.9.2 (module fms/2024.02,
# built for gcc/12.2.0 + cray-mpich/8.1.27). Casper has no equivalent
# module and no spack-stack tree, and the derecho install is tagged for
# the Derecho "zen3" CPU target so it can't just be reused. This script
# reproduces that same spack build (same source, same patch, same CMake
# options -- see .spack/spack-configure-args.txt and the fms/package.py
# recipe recorded in the derecho install) as a plain CMake build against
# Casper's native ncarenv/25.10 + gcc/14.3.0 + openmpi/5.0.8 stack.
#
# Usage: ./casper_build_fms.sh   (run on a Casper login node or inside
#                                  an execcasper session; the build itself
#                                  is a few minutes, no GPU/queue needed)
set -euo pipefail

FMS_VERSION=2024.02
FMS_SHA256=47e5740bb066f5eb032e1de163eb762c7258880a2932f4cc4e34e769e0cc2b0e
FMS_PATCH_URL="https://github.com/NOAA-GFDL/fms/pull/1559.patch?full_index=1"
FMS_PATCH_SHA256=2b12a6c35f357c3dddcfa5282576e56ab0e8e6c1ad1dab92a2c85ce3dfb815d4

INSTALL_ROOT=/glade/work/turuncu/ML-2.0/envs/casper
PREFIX=${INSTALL_ROOT}/fms/${FMS_VERSION}
MODULEDIR=${INSTALL_ROOT}/modulefiles/fms
BUILD_DIR=${TMPDIR:-/glade/derecho/scratch/$USER/casper_build}/fms-${FMS_VERSION}

module --force purge
module load ncarenv/25.10
module load gcc/14.3.0
module load openmpi/5.0.8
module load cmake/3.31.8
module load hdf5-mpi/1.14.6
module load netcdf-mpi/4.9.3

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
-- FMS ${FMS_VERSION}, built for Casper (ncarenv/25.10, gcc/14.3.0, openmpi/5.0.8)
-- Mirrors the derecho spack-stack fms/${FMS_VERSION} module (setenv fms_ROOT
-- + CMAKE_PREFIX_PATH/LD_LIBRARY_PATH) that build.sh expects.

whatis("Name : fms")
whatis("Version : ${FMS_VERSION}")
whatis("Short description : GFDL Flexible Modeling System, built for Casper")

depends_on("gcc/14.3.0")
depends_on("openmpi/5.0.8")
depends_on("netcdf-mpi/4.9.3")

prepend_path("LD_LIBRARY_PATH", "${PREFIX}/lib")
prepend_path("CMAKE_PREFIX_PATH", "${PREFIX}")
setenv("fms_ROOT", "${PREFIX}")
EOF

echo "FMS ${FMS_VERSION} installed to ${PREFIX}"
echo "Module written to ${MODULEDIR}/${FMS_VERSION}.lua"
echo "Add to casper_env_gnu.sh: module use -a ${INSTALL_ROOT}/modulefiles && module load fms/${FMS_VERSION}"
