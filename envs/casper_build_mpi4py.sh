#!/bin/bash
# Build mpi4py for Casper and register it as an Lmod module.
#
# GeoGate's embedded Python interpreter (data_aurora_client.py) needs
# `from mpi4py import MPI` to interoperate with the SAME MPI implementation
# already linked into esmx_app (openmpi/5.0.8) -- the toolkit's conda env
# (/glade/work/turuncu/ML-2.0/envs/aurora) has no mpi4py at all, by design:
# Derecho doesn't put one there either, relying instead on a separately
# spack-built py-mpi4py module (linked against cray-mpich) added to
# PYTHONPATH. This mirrors that same pattern for Casper instead of adding
# mpi4py into the shared conda env, which Derecho also uses -- building it
# standalone here avoids the risk of a wrong-MPI mpi4py shadowing
# Derecho's own cray-mpich-linked one if sys.path ordering ever changed.
#
# A plain `pip install mpi4py` would pull a prebuilt wheel bundling its
# own (incompatible) MPI; MPICC=mpicc forces pip to build from source
# against the loaded openmpi/5.0.8 instead.
#
# Usage: ./casper_build_mpi4py.sh   (run on a Casper login node or
#                                     inside an execcasper session)
set -euo pipefail

MPI4PY_VERSION=4.0.1
PYTHON_ENV=/glade/work/turuncu/ML-2.0/envs/aurora

INSTALL_ROOT=/glade/work/turuncu/ML-2.0/envs/casper
PREFIX=${INSTALL_ROOT}/mpi4py/${MPI4PY_VERSION}
MODULEDIR=${INSTALL_ROOT}/modulefiles/mpi4py
BUILD_DIR=${TMPDIR:-/glade/derecho/scratch/$USER/casper_build}/mpi4py-${MPI4PY_VERSION}

module --force purge
module load ncarenv/25.10
module load gcc/14.3.0
module load openmpi/5.0.8

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}" "${PREFIX}/python-modules"

export MPICC=mpicc
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
-- mpi4py ${MPI4PY_VERSION}, built for Casper (ncarenv/25.10, gcc/14.3.0,
-- openmpi/5.0.8), against ${PYTHON_ENV}.

whatis("Name : mpi4py")
whatis("Version : ${MPI4PY_VERSION}")
whatis("Short description : mpi4py, built for Casper against openmpi/5.0.8")

depends_on("gcc/14.3.0")
depends_on("openmpi/5.0.8")

prepend_path("PYTHONPATH", "${PREFIX}/python-modules")
EOF

echo "mpi4py ${MPI4PY_VERSION} installed to ${PREFIX}/python-modules"
echo "Module written to ${MODULEDIR}/${MPI4PY_VERSION}.lua"
echo "Add to casper_env_gnu.sh: module load mpi4py/${MPI4PY_VERSION}"
