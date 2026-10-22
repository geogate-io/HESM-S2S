#!/bin/bash
# Build ESMF (default: 8.9.0, matching the esmf-mpi/8.9.0 module this
# project otherwise relies on via NCAR's spack-stack on Derecho/Casper)
# from source and register it as an Lmod module -- for any system with
# no equivalent prebuilt module (e.g. TACC Vista, which has no NCAR
# spack-stack tree). Unlike build_fms.sh/build_conduit.sh/build_mpi4py.sh
# (plain CMake builds), ESMF uses its OWN env-var-driven GNU-make build
# system (ESMF_* variables, built IN the extracted source tree itself --
# there is no separate CMake-style build directory) -- see ESMF's own
# docs: https://earthsystemmodeling.org/docs/release/latest/ESMF_usrdoc/node10.html
#
# The env-var set below mirrors a real, working ESMF 9.0.0b16 build
# (/glade/work/turuncu/MPAS-COUPLED/PROGS/esmf_v9.0.0b16/install.sh,
# Derecho cray-mpich), generalized: that script hardcoded Derecho's own
# absolute cray-mpich compiler paths and ESMF_COMM=mpich; this one
# resolves the MPI compiler wrappers from whatever's on PATH after the
# module loads below (portable across OpenMPI/MPICH/MVAPICH2) and
# defaults ESMF_COMM to openmpi (Casper/this project's own default MPI),
# overridable for Derecho's cray-mpich or Vista's own MPI choice.
#
# Env vars (all optional -- defaults reproduce a Casper build; the ESMF_*
# build-system variables themselves can also be overridden directly if
# you need something not exposed as its own named var here):
#   ESMF_RELEASE_VERSION  which tagged release to build (default: 8.9.0;
#                          a different version needs its own SHA256 --
#                          see ESMF_RELEASE_SHA256)
#   ESMF_RELEASE_SHA256   checksum for the release tarball (default:
#                          the real v8.9.0 one; REQUIRED if you override
#                          ESMF_RELEASE_VERSION to something else)
#   INSTALL_ROOT    where to install/write the module (default: Casper's own)
#   PLATFORM_LABEL  short tag recorded in the generated module's docstring
#   MODULE_NCARENV  NCAR's own base env module; set to "" to skip entirely
#                    (there is no NCAR ncarenv module outside NCAR systems)
#   MODULE_GCC, MODULE_MPI, MODULE_CMAKE, MODULE_HDF5, MODULE_NETCDF,
#   MODULE_PIO      compiler/MPI/build-tool/IO-library modules to load;
#                    each may be set to "" to skip loading it. MODULE_PIO
#                    needs a netcdf-fortran-enabled ParallelIO (PIO)
#                    build -- see PIO_C_INCLUDE_DIR/PIO_C_LIBRARY below.
#   BUILD_DIR_ROOT  scratch root for the build (default: Casper's own)
#   PIO_C_INCLUDE_DIR / PIO_C_LIBRARY
#                   ParallelIO's own include/lib dirs -- this project's
#                   own env_gnu.sh scripts already export these after
#                   loading the parallelio module, so normally you don't
#                   need to set them here too, just source that first
#   ESMF_COMM       MPI family ESMF builds against (default: openmpi;
#                    use mpich for Cray/MPICH systems, mvapich2 for
#                    MVAPICH2, etc. -- see ESMF's own docs for valid values)
#   ESMF_COMPILER   compiler family ESMF builds against (default: gfortran)
#   ESMF_F90LINKLIBS  extra link libs some systems need (default: none --
#                      Derecho's own cray-mpich build needed "-lhdf5_mpi"
#                      for its own hdf5 module's naming quirk; set this
#                      yourself if your system's hdf5 module needs
#                      something similar)
#
# Usage: ./build_esmf.sh   (run on a login node or interactive session --
#                            ESMF's own build is CPU-heavy; consider an
#                            interactive/dev-queue session on a busy
#                            shared login node)
set -euo pipefail

ESMF_RELEASE_VERSION=${ESMF_RELEASE_VERSION:-8.9.0}
ESMF_RELEASE_SHA256=${ESMF_RELEASE_SHA256:-586e0101d76ff9842d9ad43567fae50317ee794d80293430d9f1847dec0eefa5}

PLATFORM_LABEL=${PLATFORM_LABEL:-Casper}
INSTALL_ROOT=${INSTALL_ROOT:-/glade/work/turuncu/ML-2.0/envs/casper}
MODULE_NCARENV=${MODULE_NCARENV-ncarenv/25.10}
MODULE_GCC=${MODULE_GCC-gcc/14.3.0}
MODULE_MPI=${MODULE_MPI-openmpi/5.0.8}
MODULE_CMAKE=${MODULE_CMAKE-cmake/3.31.8}
MODULE_HDF5=${MODULE_HDF5-hdf5-mpi/1.14.6}
MODULE_NETCDF=${MODULE_NETCDF-netcdf-mpi/4.9.3}
MODULE_PIO=${MODULE_PIO-parallelio/2.6.6}
BUILD_DIR_ROOT=${BUILD_DIR_ROOT:-/glade/derecho/scratch/$USER/casper_build}

ESMF_COMM=${ESMF_COMM:-openmpi}
ESMF_COMPILER=${ESMF_COMPILER:-gfortran}
ESMF_F90LINKLIBS=${ESMF_F90LINKLIBS:-}

PREFIX=${INSTALL_ROOT}/esmf/${ESMF_RELEASE_VERSION}
MODULEDIR=${INSTALL_ROOT}/modulefiles/esmf-mpi
BUILD_DIR=${TMPDIR:-${BUILD_DIR_ROOT}}/esmf-${ESMF_RELEASE_VERSION}

module --force purge
[ -n "${MODULE_NCARENV}" ] && module load "${MODULE_NCARENV}"
[ -n "${MODULE_GCC}" ] && module load "${MODULE_GCC}"
[ -n "${MODULE_MPI}" ] && module load "${MODULE_MPI}"
[ -n "${MODULE_CMAKE}" ] && module load "${MODULE_CMAKE}"
[ -n "${MODULE_HDF5}" ] && module load "${MODULE_HDF5}"
[ -n "${MODULE_NETCDF}" ] && module load "${MODULE_NETCDF}"
[ -n "${MODULE_PIO}" ] && module load "${MODULE_PIO}"

# This project's own env_gnu.sh scripts already export these directly
# (derived from NCAR_ROOT_PARALLELIO, the NCAR module tree's own
# convention on Casper/Derecho) -- only re-derive here as a fallback.
# NCAR_ROOT_PARALLELIO itself won't exist on a non-NCAR system like TACC
# Vista, so there, PIO_C_INCLUDE_DIR/PIO_C_LIBRARY must be set explicitly
# (or source this project's own env_gnu.sh first, once it has a Vista
# variant) rather than relying on this fallback.
: "${PIO_C_INCLUDE_DIR:=${NCAR_ROOT_PARALLELIO:-}/include}"
: "${PIO_C_LIBRARY:=${NCAR_ROOT_PARALLELIO:-}/lib}"
if [ ! -d "${PIO_C_INCLUDE_DIR}" ]; then
  echo "build_esmf.sh: can't find ParallelIO's include dir (${PIO_C_INCLUDE_DIR} doesn't" >&2
  echo "  exist, and NCAR_ROOT_PARALLELIO is unset) -- set PIO_C_INCLUDE_DIR/PIO_C_LIBRARY" >&2
  echo "  yourself (there is no NCAR_ROOT_PARALLELIO convention outside NCAR systems)." >&2
  exit 1
fi

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

curl -sL "https://github.com/esmf-org/esmf/archive/refs/tags/v${ESMF_RELEASE_VERSION}.tar.gz" -o esmf.tar.gz
echo "${ESMF_RELEASE_SHA256}  esmf.tar.gz" | sha256sum -c -
tar xzf esmf.tar.gz
cd "esmf-${ESMF_RELEASE_VERSION}"

# ESMF's own build system: env-var driven, built in place (ESMF_DIR must
# be this source tree itself, not a separate build dir) -- no `cmake`/
# `configure` step, just `make`/`make install` once these are set.
export ESMF_DIR=${PWD}
export ESMF_BOPT=O
export ESMF_COMM
export ESMF_COMPILER
export ESMF_OS=Linux
export ESMF_INSTALL_PREFIX=${PREFIX}
export ESMF_INSTALL_BINDIR=bin
export ESMF_INSTALL_LIBDIR=lib
export ESMF_INSTALL_MODDIR=include
export ESMF_LAPACK=internal
export ESMF_NETCDF=nc-config
export ESMF_NFCONFIG=nf-config
export ESMF_PIO=external
export ESMF_PIO_INCLUDE=${PIO_C_INCLUDE_DIR}
export ESMF_PIO_LIBPATH=${PIO_C_LIBRARY}
export ESMF_SHARED_LIB_BUILD=OFF
export ESMF_C=$(command -v mpicc)
export ESMF_CXX=$(command -v mpicxx)
export ESMF_F90=$(command -v mpif90)
[ -n "${ESMF_F90LINKLIBS}" ] && export ESMF_F90LINKLIBS

make
make install

ESMFMKFILE_PATH=${PREFIX}/lib/esmf.mk
if [ ! -f "${ESMFMKFILE_PATH}" ]; then
  echo "build_esmf.sh: expected esmf.mk at ${ESMFMKFILE_PATH} but it's not there --" >&2
  echo "  check ESMF's own install log above for where it actually landed." >&2
  exit 1
fi

mkdir -p "${MODULEDIR}"
cat > "${MODULEDIR}/${ESMF_RELEASE_VERSION}.lua" <<EOF
-- -*- lua -*-
-- ESMF ${ESMF_RELEASE_VERSION}, built for ${PLATFORM_LABEL} (${MODULE_GCC:-no gcc module},
-- ${MODULE_MPI:-no MPI module}), ESMF_COMM=${ESMF_COMM}, ESMF_COMPILER=${ESMF_COMPILER}.

whatis("Name : esmf-mpi")
whatis("Version : ${ESMF_RELEASE_VERSION}")
whatis("Short description : Earth System Modeling Framework, built for ${PLATFORM_LABEL}")

$( [ -n "${MODULE_GCC}" ] && echo "depends_on(\"${MODULE_GCC}\")" )
$( [ -n "${MODULE_MPI}" ] && echo "depends_on(\"${MODULE_MPI}\")" )
$( [ -n "${MODULE_NETCDF}" ] && echo "depends_on(\"${MODULE_NETCDF}\")" )
$( [ -n "${MODULE_PIO}" ] && echo "depends_on(\"${MODULE_PIO}\")" )

prepend_path("LD_LIBRARY_PATH", "${PREFIX}/lib")
prepend_path("PATH", "${PREFIX}/bin")
prepend_path("CMAKE_PREFIX_PATH", "${PREFIX}")
setenv("ESMF_ROOT", "${PREFIX}")
setenv("ESMFMKFILE", "${ESMFMKFILE_PATH}")
EOF

echo "ESMF ${ESMF_RELEASE_VERSION} installed to ${PREFIX}"
echo "Module written to ${MODULEDIR}/${ESMF_RELEASE_VERSION}.lua"
echo "Add to your env_gnu.sh: module use -a ${INSTALL_ROOT}/modulefiles && module load esmf-mpi/${ESMF_RELEASE_VERSION}"
