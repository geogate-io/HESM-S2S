#!/bin/bash
# Build Conduit 0.9.2 for Casper and register it as an Lmod module.
#
# GeoGate's Python plugin (GEOGATE_USE_PYTHON=ON) needs Conduit's
# include dir and python module dir (CONDUIT_INCLUDE_DIRS /
# CONDUIT_PYTHON_MODULE_DIR), independent of Catalyst -- see
# src/GeoGate/src/plugins/python/CMakeLists.txt. Catalyst/libcatalyst and
# ParaView are intentionally NOT built here: build.sh should be run with
# -DGEOGATE_USE_CATALYST=OFF on Casper.
#
# Built with +fortran +mpi +python +shared, matching the derecho spack
# build (conduit/package.py params: fortran, mpi, python, shared all
# true), but using the toolkit's own conda env
# (/glade/work/turuncu/ML-2.0/envs/aurora) as the Python, since that is
# the same interpreter GeoGate itself links against at build.sh time
# (PYTHON_ENV is put first on PATH, and GeoGate's SetupPython.cmake just
# does find_package(PythonInterp) against whatever python3 it finds).
#
# Usage: ./casper_build_conduit.sh   (run on a Casper login node or
#                                      inside an execcasper session)
set -euo pipefail

CONDUIT_VERSION=0.9.2
CONDUIT_SHA256=45d5a4eccd0fc978d153d29c440c53c483b8f29dfcf78ddcc9aa15c59b257177
PYTHON_ENV=/glade/work/turuncu/ML-2.0/envs/aurora

INSTALL_ROOT=/glade/work/turuncu/ML-2.0/envs/casper
PREFIX=${INSTALL_ROOT}/conduit/${CONDUIT_VERSION}
MODULEDIR=${INSTALL_ROOT}/modulefiles/conduit
BUILD_DIR=${TMPDIR:-/glade/derecho/scratch/$USER/casper_build}/conduit-${CONDUIT_VERSION}

module --force purge
module load ncarenv/25.10
module load gcc/14.3.0
module load openmpi/5.0.8
module load cmake/3.31.8

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

curl -sL "https://github.com/LLNL/conduit/releases/download/v${CONDUIT_VERSION}/conduit-v${CONDUIT_VERSION}-src-with-blt.tar.gz" -o conduit.tar.gz
echo "${CONDUIT_SHA256}  conduit.tar.gz" | sha256sum -c -
tar xzf conduit.tar.gz
cd "conduit-v${CONDUIT_VERSION}"

# Workaround: this conda Python's sysconfig reports a static libpython
# name (LDLIBRARY=LIBRARY=libpython3.12.a) even though only a shared
# libpython3.12.so was actually installed (Py_ENABLE_SHARED=0 in its
# sysconfig data despite the .so being present -- a known conda-forge
# Python 3.12 quirk). Conduit's SetupPython.cmake only tries the names
# sysconfig reports, so without this it always hits a hard
# "Failed to find main library" error. Add one more fallback check.
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
-- Conduit ${CONDUIT_VERSION}, built for Casper (ncarenv/25.10, gcc/14.3.0,
-- openmpi/5.0.8), Python bindings against ${PYTHON_ENV}.

whatis("Name : conduit")
whatis("Version : ${CONDUIT_VERSION}")
whatis("Short description : Conduit hierarchical data library, built for Casper")

depends_on("gcc/14.3.0")
depends_on("openmpi/5.0.8")

prepend_path("LD_LIBRARY_PATH", "${PREFIX}/lib")
prepend_path("CMAKE_PREFIX_PATH", "${PREFIX}")
setenv("CONDUIT_ROOT", "${PREFIX}")
EOF

echo "Conduit ${CONDUIT_VERSION} installed to ${PREFIX}"
echo "Module written to ${MODULEDIR}/${CONDUIT_VERSION}.lua"
echo "Add to casper_env_gnu.sh: module use -a ${INSTALL_ROOT}/modulefiles && module load conduit/${CONDUIT_VERSION}"
