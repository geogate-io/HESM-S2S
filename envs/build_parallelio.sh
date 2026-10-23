#!/bin/bash
# Build ParallelIO (PIO; default: 2.6.6, matching the parallelio/2.6.6
# module this project otherwise relies on via NCAR's module tree on
# Casper/Derecho) from source and register it as an Lmod module -- for
# any system with no equivalent prebuilt module (e.g. TACC Vista).
#
# CMake options below mirror a real, proven build -- the epicufsrt
# spack-stack-1.9.2 parallelio@2.6.2 recipe on Derecho (see its own
# generated modulefile's "Configure options" whatis string:
# .../spack-stack-1.9.2/envs/ue-gcc-12.2.0/install/modulefiles/.../
# parallelio/2.6.2.lua, cross-checked against that env's own spack.lock
# for the exact dependency set: netcdf-c, netcdf-fortran, parallel-netcdf,
# +fortran +mpi +pnetcdf +shared ~ncint ~logging ~timing). Two of that
# recipe's flags don't carry over as-is to 2.6.6's own source layout,
# though (confirmed directly against the real 2.6.6 source tree, not
# assumed): spack's -DUSER_CMAKE_MODULE_PATH/-DGENF90_PATH pointed at
# CMake_Fortran_utils/genf90 subdirectories of ITS OWN separately-staged
# spack build directory, which don't exist in a plain source checkout.
# PIO's own CMakeLists.txt handles both as OPTIONAL now, with its own
# fallback: an implicit `git clone` of each at configure time if not
# given. Rather than relying on that implicit clone (whether it works
# depends on the build node's own git/network setup, which this script
# would rather control explicitly, the same way every other dependency
# here is an explicit curl+sha256 step, not an implicit fetch): this
# script clones CMake_Fortran_utils itself, and points GENF90_PATH at
# the genf90.pl PIO already bundles under its own scripts/ dir (no clone
# needed for that one at all).
#
# Env vars (all optional -- defaults reproduce a Casper build):
#   PIO_RELEASE_VERSION  which tagged release to build (default: 2.6.6;
#                         PIO's own GitHub tags are "pio2_6_6"-style, not
#                         semver -- this script converts automatically)
#   PIO_RELEASE_SHA256    checksum for the release tarball (default: the
#                          real pio2_6_6 one; REQUIRED if you override
#                          PIO_RELEASE_VERSION to something else)
#   INSTALL_ROOT    where to install/write the module (default: Casper's own)
#   PLATFORM_LABEL  short tag recorded in the generated module's docstring
#   MODULE_NCARENV  NCAR's own base env module; set to "" to skip entirely
#                    (there is no NCAR ncarenv module outside NCAR systems)
#   MODULE_GCC, MODULE_MPI, MODULE_CMAKE, MODULE_NETCDF, MODULE_PNETCDF
#                    compiler/MPI/build-tool/IO-library modules to load;
#                    each may be set to "" to skip loading it. MODULE_PNETCDF
#                    is only loaded/used at all if PIO_ENABLE_PNETCDF=ON.
#   BUILD_DIR_ROOT  scratch root for the build (default: Casper's own)
#   NETCDF_C_PATH / NETCDF_FORTRAN_PATH
#                   netCDF-C/netCDF-Fortran install roots PIO builds
#                   against. Default: both NCAR_ROOT_NETCDF (Casper's
#                   netcdf-mpi module bundles C+Fortran together, unlike
#                   Derecho's separate netcdf-c/netcdf-fortran packages --
#                   set these two separately yourself if your system
#                   splits them, or has no NCAR_ROOT_NETCDF convention at
#                   all, as on a non-NCAR system like Vista).
#   PIO_ENABLE_PNETCDF  ON to match the proven Derecho recipe exactly
#                        (needs a working parallel-netcdf module/PNETCDF_PATH);
#                        default OFF -- this project's own esmxRun.yaml
#                        already runs with pio_typename: netcdf, not
#                        pnetcdf, so this isn't actually exercised here.
#   PNETCDF_PATH    parallel-netcdf install root (only used if
#                    PIO_ENABLE_PNETCDF=ON; default: NCAR_ROOT_PARALLEL_NETCDF)
#
# Usage: ./build_parallelio.sh   (run on a login node or interactive
#                                  session; needs outbound git/https
#                                  access to clone CMake_Fortran_utils)
set -euo pipefail

PIO_RELEASE_VERSION=${PIO_RELEASE_VERSION:-2.6.6}
PIO_RELEASE_SHA256=${PIO_RELEASE_SHA256:-e32e018a521d38c9424940c7cfa7e9b1931b605f3511ee7ab3a718b69faeeb04}
PIO_GIT_TAG="pio${PIO_RELEASE_VERSION//./_}"

PLATFORM_LABEL=${PLATFORM_LABEL:-Casper}
INSTALL_ROOT=${INSTALL_ROOT:-/glade/work/turuncu/ML-2.0/envs/casper}
MODULE_NCARENV=${MODULE_NCARENV-ncarenv/25.10}
MODULE_GCC=${MODULE_GCC-gcc/14.3.0}
MODULE_MPI=${MODULE_MPI-openmpi/5.0.8}
MODULE_CMAKE=${MODULE_CMAKE-cmake/3.31.8}
MODULE_HDF5=${MODULE_HDF5-hdf5-mpi/1.14.6}
MODULE_NETCDF=${MODULE_NETCDF-netcdf-mpi/4.9.3}
BUILD_DIR_ROOT=${BUILD_DIR_ROOT:-/glade/derecho/scratch/$USER/casper_build}

PIO_ENABLE_PNETCDF=${PIO_ENABLE_PNETCDF:-OFF}
MODULE_PNETCDF=${MODULE_PNETCDF-parallel-netcdf/1.14.1}

PREFIX=${INSTALL_ROOT}/parallelio/${PIO_RELEASE_VERSION}
MODULEDIR=${INSTALL_ROOT}/modulefiles/parallelio
BUILD_DIR=${TMPDIR:-${BUILD_DIR_ROOT}}/parallelio-${PIO_RELEASE_VERSION}

module --force purge
[ -n "${MODULE_NCARENV}" ] && module load "${MODULE_NCARENV}"
[ -n "${MODULE_GCC}" ] && module load "${MODULE_GCC}"
[ -n "${MODULE_MPI}" ] && module load "${MODULE_MPI}"
[ -n "${MODULE_CMAKE}" ] && module load "${MODULE_CMAKE}"
# netCDF's netcdf4/parallel support depends on HDF5 -- must load before
# netcdf-mpi (NCAR's module tree is hierarchical: netcdf-mpi may not even
# be visible/correctly initialized without hdf5-mpi loaded first, same
# order this project's own env_gnu.sh scripts always use).
[ -n "${MODULE_HDF5}" ] && module load "${MODULE_HDF5}"
[ -n "${MODULE_NETCDF}" ] && module load "${MODULE_NETCDF}"
if [ "${PIO_ENABLE_PNETCDF}" = "ON" ] && [ -n "${MODULE_PNETCDF}" ]; then
  module load "${MODULE_PNETCDF}"
fi

# nc-config/nf-config ship with netCDF-C/-Fortran itself and work on any
# system (unlike NCAR_ROOT_NETCDF, which only exists on NCAR's own module
# tree) -- try those first, then NCAR_ROOT_NETCDF as a secondary hint.
if [ -z "${NETCDF_C_PATH:-}" ] && command -v nc-config > /dev/null 2>&1; then
  NETCDF_C_PATH=$(nc-config --prefix)
fi
if [ -z "${NETCDF_FORTRAN_PATH:-}" ] && command -v nf-config > /dev/null 2>&1; then
  NETCDF_FORTRAN_PATH=$(nf-config --prefix)
fi
: "${NETCDF_C_PATH:=${NCAR_ROOT_NETCDF:-}}"
: "${NETCDF_FORTRAN_PATH:=${NCAR_ROOT_NETCDF:-}}"
if [ ! -d "${NETCDF_C_PATH}" ]; then
  echo "build_parallelio.sh: can't find netCDF-C (nc-config not on PATH, NCAR_ROOT_NETCDF" >&2
  echo "  unset, and NETCDF_C_PATH=${NETCDF_C_PATH:-<unset>} doesn't exist) -- set" >&2
  echo "  NETCDF_C_PATH/NETCDF_FORTRAN_PATH yourself, or check MODULE_NETCDF/MODULE_HDF5" >&2
  echo "  actually loaded without error above." >&2
  exit 1
fi
if [ "${PIO_ENABLE_PNETCDF}" = "ON" ]; then
  : "${PNETCDF_PATH:=${NCAR_ROOT_PARALLEL_NETCDF:-}}"
  if [ ! -d "${PNETCDF_PATH}" ]; then
    echo "build_parallelio.sh: PIO_ENABLE_PNETCDF=ON but can't find parallel-netcdf" >&2
    echo "  (${PNETCDF_PATH:-<unset>} doesn't exist) -- set PNETCDF_PATH yourself." >&2
    exit 1
  fi
fi

# Some systems install netCDF's libraries under lib64/ rather than lib/
# (confirmed directly on TACC Vista: NetCDF_Fortran_LIBDIR there resolves
# to .../lib64, found correctly via pkg-config -- but PIO's own piof
# CMake target links against the bare "netcdff" library name without
# carrying that pkg-config-derived -L path through to the actual link
# command, producing "cannot find -lnetcdff" despite the library
# genuinely existing and being correctly located internally). Rather than
# depend on PIO's own internal target wiring picking up the right -L,
# pass both candidate lib dirs explicitly and unconditionally as linker
# search paths -- harmless if one doesn't exist (the linker just ignores
# a nonexistent -L), fixes it regardless of which one is real here.
EXTRA_LINKER_FLAGS=""
for root in "${NETCDF_C_PATH}" "${NETCDF_FORTRAN_PATH}"; do
  for libdir in lib lib64; do
    [ -d "${root}/${libdir}" ] && EXTRA_LINKER_FLAGS="${EXTRA_LINKER_FLAGS} -L${root}/${libdir}"
  done
done

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

curl -sL "https://github.com/NCAR/ParallelIO/archive/refs/tags/${PIO_GIT_TAG}.tar.gz" -o pio.tar.gz
echo "${PIO_RELEASE_SHA256}  pio.tar.gz" | sha256sum -c -
tar xzf pio.tar.gz
cd "ParallelIO-${PIO_GIT_TAG}"

# Explicit, visible fetch of the one build-time helper PIO's own
# CMakeLists.txt would otherwise `git clone` implicitly if
# -DUSER_CMAKE_MODULE_PATH isn't given -- see this script's own header.
git clone --depth 1 https://github.com/CESM-Development/CMake_Fortran_utils "${BUILD_DIR}/CMake_Fortran_utils"

CMAKE_ARGS=(
  -S . -B build
  -DCMAKE_INSTALL_PREFIX="${PREFIX}"
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_C_COMPILER=mpicc
  -DCMAKE_Fortran_COMPILER=mpif90
  -DNetCDF_C_PATH:STRING="${NETCDF_C_PATH}"
  -DNetCDF_Fortran_PATH:STRING="${NETCDF_FORTRAN_PATH}"
  -DUSER_CMAKE_MODULE_PATH:STRING="${BUILD_DIR}/CMake_Fortran_utils"
  -DGENF90_PATH:STRING="${PWD}/scripts"
  -DCMAKE_EXE_LINKER_FLAGS:STRING="${EXTRA_LINKER_FLAGS}"
  -DCMAKE_SHARED_LINKER_FLAGS:STRING="${EXTRA_LINKER_FLAGS}"
  -DBUILD_SHARED_LIBS:BOOL=ON
  -DPIO_ENABLE_EXAMPLES:BOOL=OFF
  -DPIO_ENABLE_TIMING:BOOL=OFF
  -DPIO_ENABLE_LOGGING:BOOL=OFF
  -DPIO_ENABLE_FORTRAN:BOOL=ON
)
if [ "${PIO_ENABLE_PNETCDF}" = "ON" ]; then
  CMAKE_ARGS+=(-DPnetCDF_C_PATH:STRING="${PNETCDF_PATH}")
fi

cmake "${CMAKE_ARGS[@]}"
cmake --build build -j8
cmake --install build

mkdir -p "${MODULEDIR}"
cat > "${MODULEDIR}/${PIO_RELEASE_VERSION}.lua" <<EOF
-- -*- lua -*-
-- ParallelIO ${PIO_RELEASE_VERSION}, built for ${PLATFORM_LABEL} (${MODULE_GCC:-no gcc module},
-- ${MODULE_MPI:-no MPI module}), against netCDF at ${NETCDF_C_PATH}.
-- PIO_ENABLE_PNETCDF=${PIO_ENABLE_PNETCDF}

whatis("Name : parallelio")
whatis("Version : ${PIO_RELEASE_VERSION}")
whatis("Short description : The Parallel IO libraries (PIO), built for ${PLATFORM_LABEL}")

$( [ -n "${MODULE_GCC}" ] && echo "depends_on(\"${MODULE_GCC}\")" )
$( [ -n "${MODULE_MPI}" ] && echo "depends_on(\"${MODULE_MPI}\")" )
$( [ -n "${MODULE_HDF5}" ] && echo "depends_on(\"${MODULE_HDF5}\")" )
$( [ -n "${MODULE_NETCDF}" ] && echo "depends_on(\"${MODULE_NETCDF}\")" )
$( [ "${PIO_ENABLE_PNETCDF}" = "ON" ] && [ -n "${MODULE_PNETCDF}" ] && echo "depends_on(\"${MODULE_PNETCDF}\")" )

prepend_path("LD_LIBRARY_PATH", "${PREFIX}/lib")
prepend_path("CPATH", "${PREFIX}/include")
prepend_path("CMAKE_PREFIX_PATH", "${PREFIX}")
setenv("PIO_C_PATH", "${PREFIX}")
setenv("PIO_Fortran_PATH", "${PREFIX}")
setenv("parallelio_ROOT", "${PREFIX}")
EOF

echo "ParallelIO ${PIO_RELEASE_VERSION} installed to ${PREFIX}"
echo "Module written to ${MODULEDIR}/${PIO_RELEASE_VERSION}.lua"
echo "Add to your env_gnu.sh: module use -a ${INSTALL_ROOT}/modulefiles && module load parallelio/${PIO_RELEASE_VERSION}"
