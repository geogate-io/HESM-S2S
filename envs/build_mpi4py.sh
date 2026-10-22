#!/bin/bash
# Build mpi4py from source and register it as an Lmod module, on any
# system with Lmod + an MPI compiler wrapper (mpicc) -- originally
# written for Casper, now parameterized via env vars so the same script
# also works on e.g. TACC Vista (its own module names are NOT known
# here -- set them yourself from `module avail`/`module spider` on that
# system; nothing below is a guess at Vista's values).
#
# GeoGate's embedded Python interpreter (data_aurora_client.py) needs
# `from mpi4py import MPI` to interoperate with the SAME MPI implementation
# already linked into esmx_app -- the toolkit's conda env ($PYTHON_ENV) has
# no mpi4py at all, by design: Derecho doesn't put one there either,
# relying instead on a separately spack-built py-mpi4py module (linked
# against cray-mpich) added to PYTHONPATH. This mirrors that same pattern
# for any other system instead of adding mpi4py into the shared conda
# env, which Derecho also uses -- building it standalone here avoids the
# risk of a wrong-MPI mpi4py shadowing Derecho's own cray-mpich-linked
# one if sys.path ordering ever changed.
#
# A plain `pip install mpi4py` would pull a prebuilt wheel bundling its
# own (incompatible) MPI; MPICC=mpicc (or whatever $MPICC_WRAPPER names)
# forces pip to build from source against the loaded MPI module instead.
#
# Env vars (all optional -- defaults reproduce the original Casper build
# exactly, so plain `./build_mpi4py.sh` on Casper is unchanged):
#   PYTHON_ENV      conda/venv root whose bin/python3 mpi4py builds against
#   INSTALL_ROOT    where to install/write the module (default: Casper's own)
#   PLATFORM_LABEL  short tag recorded in the generated module's docstring
#   MODULE_NCARENV  NCAR's own base env module; set to "" to skip entirely
#                    (there is no NCAR ncarenv module outside NCAR systems)
#   MODULE_GCC, MODULE_MPI
#                    compiler/MPI modules to load; each may be set to ""
#                    to skip loading it (e.g. if already loaded by the
#                    calling environment)
#   MPICC_WRAPPER   the MPI C compiler wrapper name (default: mpicc --
#                    standard across OpenMPI/MPICH/Intel MPI/MVAPICH2)
#   BUILD_DIR_ROOT  scratch root for the build (default: Casper's own)
#
# Usage: ./build_mpi4py.sh   (run on a login node or interactive session)
set -euo pipefail

MPI4PY_VERSION=4.0.1

PLATFORM_LABEL=${PLATFORM_LABEL:-Casper}
PYTHON_ENV=${PYTHON_ENV:-/glade/work/turuncu/ML-2.0/envs/aurora}
INSTALL_ROOT=${INSTALL_ROOT:-/glade/work/turuncu/ML-2.0/envs/casper}
MODULE_NCARENV=${MODULE_NCARENV-ncarenv/25.10}
MODULE_GCC=${MODULE_GCC-gcc/14.3.0}
MODULE_MPI=${MODULE_MPI-openmpi/5.0.8}
MPICC_WRAPPER=${MPICC_WRAPPER:-mpicc}
BUILD_DIR_ROOT=${BUILD_DIR_ROOT:-/glade/derecho/scratch/$USER/casper_build}

PREFIX=${INSTALL_ROOT}/mpi4py/${MPI4PY_VERSION}
MODULEDIR=${INSTALL_ROOT}/modulefiles/mpi4py
BUILD_DIR=${TMPDIR:-${BUILD_DIR_ROOT}}/mpi4py-${MPI4PY_VERSION}

module --force purge
[ -n "${MODULE_NCARENV}" ] && module load "${MODULE_NCARENV}"
[ -n "${MODULE_GCC}" ] && module load "${MODULE_GCC}"
[ -n "${MODULE_MPI}" ] && module load "${MODULE_MPI}"

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}" "${PREFIX}/python-modules"

export MPICC=${MPICC_WRAPPER}
"${PYTHON_ENV}/bin/python3" -m pip install \
  --no-binary mpi4py \
  --target "${PREFIX}/python-modules" \
  --no-deps \
  --cache-dir "${BUILD_DIR}" \
  "mpi4py==${MPI4PY_VERSION}"

"${PYTHON_ENV}/bin/python3" -c "
import sys; sys.path.insert(0, '${PREFIX}/python-modules')
from mpi4py import MPI
print('mpi4py OK, MPI library:', MPI.Get_library_version().splitlines()[0])
"

mkdir -p "${MODULEDIR}"
cat > "${MODULEDIR}/${MPI4PY_VERSION}.lua" <<EOF
-- -*- lua -*-
-- mpi4py ${MPI4PY_VERSION}, built for ${PLATFORM_LABEL} (${MODULE_GCC:-no gcc module},
-- ${MODULE_MPI:-no MPI module}), against ${PYTHON_ENV}.

whatis("Name : mpi4py")
whatis("Version : ${MPI4PY_VERSION}")
whatis("Short description : mpi4py, built for ${PLATFORM_LABEL} against ${MODULE_MPI:-the loaded MPI}")

$( [ -n "${MODULE_GCC}" ] && echo "depends_on(\"${MODULE_GCC}\")" )
$( [ -n "${MODULE_MPI}" ] && echo "depends_on(\"${MODULE_MPI}\")" )

prepend_path("PYTHONPATH", "${PREFIX}/python-modules")
EOF

echo "mpi4py ${MPI4PY_VERSION} installed to ${PREFIX}/python-modules"
echo "Module written to ${MODULEDIR}/${MPI4PY_VERSION}.lua"
echo "Add to your env_gnu.sh: module load mpi4py/${MPI4PY_VERSION}"
