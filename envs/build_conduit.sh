#!/bin/bash
# Build Conduit 0.9.2 from source and register it as an Lmod module, on
# any system with Lmod + a C/C++/Fortran-capable MPI compiler wrapper --
# originally written for Casper, now parameterized via env vars so the
# same script also works on e.g. TACC Vista (its own module names are
# NOT known here -- set them yourself from `module avail`/`module
# spider` on that system; nothing below is a guess at Vista's values).
#
# GeoGate's Python plugin (GEOGATE_USE_PYTHON=ON) needs Conduit's
# include dir and python module dir (CONDUIT_INCLUDE_DIRS /
# CONDUIT_PYTHON_MODULE_DIR), independent of Catalyst -- see
# src/GeoGate/src/plugins/python/CMakeLists.txt. Catalyst/libcatalyst and
# ParaView are intentionally NOT built here: build.sh should be run with
# -DGEOGATE_USE_CATALYST=OFF on a system provisioned this way.
#
# Built with +fortran +mpi +python +shared, matching the derecho spack
# build (conduit/package.py params: fortran, mpi, python, shared all
# true), but using the toolkit's own conda env ($PYTHON_ENV) as the
# Python, since that is the same interpreter GeoGate itself links against
# at build.sh time (PYTHON_ENV is put first on PATH, and GeoGate's
# SetupPython.cmake just does find_package(PythonInterp) against
# whatever python3 it finds).
#
# Env vars (all optional -- defaults reproduce the original Casper build
# exactly, so plain `./build_conduit.sh` on Casper is unchanged):
#   PYTHON_ENV      conda/venv root whose bin/python3 Conduit builds against
#   INSTALL_ROOT    where to install/write the module (default: Casper's own)
#   PLATFORM_LABEL  short tag recorded in the generated module's docstring
#   MODULE_NCARENV  NCAR's own base env module; set to "" to skip entirely
#                    (there is no NCAR ncarenv module outside NCAR systems)
#   MODULE_GCC, MODULE_MPI, MODULE_CMAKE
#                    compiler/MPI/build-tool modules to load; each may be
#                    set to "" to skip loading it (e.g. if already loaded
#                    by the calling environment)
#   BUILD_DIR_ROOT  scratch root for the build (default: Casper's own)
#
# Usage: ./build_conduit.sh   (run on a login node or interactive session)
set -euo pipefail

CONDUIT_VERSION=0.9.2
CONDUIT_SHA256=45d5a4eccd0fc978d153d29c440c53c483b8f29dfcf78ddcc9aa15c59b257177

PLATFORM_LABEL=${PLATFORM_LABEL:-Casper}
PYTHON_ENV=${PYTHON_ENV:-/glade/work/turuncu/ML-2.0/envs/aurora}
INSTALL_ROOT=${INSTALL_ROOT:-/glade/work/turuncu/ML-2.0/envs/casper}
MODULE_NCARENV=${MODULE_NCARENV-ncarenv/25.10}
MODULE_GCC=${MODULE_GCC-gcc/14.3.0}
MODULE_MPI=${MODULE_MPI-openmpi/5.0.8}
MODULE_CMAKE=${MODULE_CMAKE-cmake/3.31.8}
BUILD_DIR_ROOT=${BUILD_DIR_ROOT:-/glade/derecho/scratch/$USER/casper_build}

PREFIX=${INSTALL_ROOT}/conduit/${CONDUIT_VERSION}
MODULEDIR=${INSTALL_ROOT}/modulefiles/conduit
BUILD_DIR=${TMPDIR:-${BUILD_DIR_ROOT}}/conduit-${CONDUIT_VERSION}

module --force purge
[ -n "${MODULE_NCARENV}" ] && module load "${MODULE_NCARENV}"
[ -n "${MODULE_GCC}" ] && module load "${MODULE_GCC}"
[ -n "${MODULE_MPI}" ] && module load "${MODULE_MPI}"
[ -n "${MODULE_CMAKE}" ] && module load "${MODULE_CMAKE}"

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

curl -sL "https://github.com/LLNL/conduit/releases/download/v${CONDUIT_VERSION}/conduit-v${CONDUIT_VERSION}-src-with-blt.tar.gz" -o conduit.tar.gz
echo "${CONDUIT_SHA256}  conduit.tar.gz" | sha256sum -c -
tar xzf conduit.tar.gz
cd "conduit-v${CONDUIT_VERSION}"

# Workaround: a conda Python's sysconfig can report a static libpython
# name (LDLIBRARY=LIBRARY=libpython3.12.a) even though only a shared
# libpython3.12.so was actually installed (Py_ENABLE_SHARED=0 in its
# sysconfig data despite the .so being present -- a known conda-forge
# Python 3.12 quirk, not specific to any one system). Conduit's
# SetupPython.cmake only tries the names sysconfig reports, so without
# this it always hits a hard "Failed to find main library" error. Add one
# more fallback check.
cat > /tmp/conduit_py_fallback.cmake.$$ <<'EOF'
            if(NOT EXISTS ${PYTHON_LIBRARY})
                set(_PYTHON_LIBRARY_TEST "${PYTHON_CONFIG_LIBDIR}/libpython${PYTHON_CONFIG_VERSION}.so")
                message(STATUS "Checking for python library at: ${_PYTHON_LIBRARY_TEST}")
                if(EXISTS ${_PYTHON_LIBRARY_TEST})
                    set(PYTHON_LIBRARY ${_PYTHON_LIBRARY_TEST})
                endif()
            endif()
EOF
sed -i "/set(PYTHON_LIBRARY \"\")/r /tmp/conduit_py_fallback.cmake.$$" src/cmake/thirdparty/SetupPython.cmake
rm -f /tmp/conduit_py_fallback.cmake.$$

cmake -S src -B build \
  -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER=mpicc \
  -DCMAKE_CXX_COMPILER=mpicxx \
  -DCMAKE_Fortran_COMPILER=mpif90 \
  -DBUILD_SHARED_LIBS:BOOL=ON \
  -DENABLE_MPI:BOOL=ON \
  -DENABLE_FORTRAN:BOOL=ON \
  -DENABLE_PYTHON:BOOL=ON \
  -DPYTHON_EXECUTABLE="${PYTHON_ENV}/bin/python3" \
  -DENABLE_TESTS:BOOL=OFF \
  -DENABLE_EXAMPLES:BOOL=OFF \
  -DENABLE_UTILS:BOOL=ON \
  -DENABLE_DOCS:BOOL=OFF

cmake --build build -j8
cmake --install build

mkdir -p "${MODULEDIR}"
cat > "${MODULEDIR}/${CONDUIT_VERSION}.lua" <<EOF
-- -*- lua -*-
-- Conduit ${CONDUIT_VERSION}, built for ${PLATFORM_LABEL} (${MODULE_GCC:-no gcc module},
-- ${MODULE_MPI:-no MPI module}), Python bindings against ${PYTHON_ENV}.

whatis("Name : conduit")
whatis("Version : ${CONDUIT_VERSION}")
whatis("Short description : Conduit hierarchical data library, built for ${PLATFORM_LABEL}")

$( [ -n "${MODULE_GCC}" ] && echo "depends_on(\"${MODULE_GCC}\")" )
$( [ -n "${MODULE_MPI}" ] && echo "depends_on(\"${MODULE_MPI}\")" )

prepend_path("LD_LIBRARY_PATH", "${PREFIX}/lib")
prepend_path("CMAKE_PREFIX_PATH", "${PREFIX}")
setenv("CONDUIT_ROOT", "${PREFIX}")
EOF

echo "Conduit ${CONDUIT_VERSION} installed to ${PREFIX}"
echo "Module written to ${MODULEDIR}/${CONDUIT_VERSION}.lua"
echo "Add to your env_gnu.sh: module use -a ${INSTALL_ROOT}/modulefiles && module load conduit/${CONDUIT_VERSION}"
