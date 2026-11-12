#!/bin/bash
set -eo pipefail

OMPI=/opt/apps/gcc14/openmpi/5.0.11

module load gcc/14.2.0
module load openmpi/5.0.11
module load cmake/4.1.1
module load phdf5/1.14.6
module load parallelnetcdf/4.9.2

for t in mpicc mpicxx mpif90 nc-config nf-config; do
  p=$(command -v $t) || { echo "ERROR: $t not found on PATH" >&2; exit 1; }
  case "$p" in
    $WORK/envs/hybrid-s2s/*)
      echo "ERROR: $t resolves to $p -- run 'conda deactivate' first" >&2
      exit 1 ;;
  esac
done

# PIO
#INSTALL_ROOT=$WORK/envs \
#BUILD_DIR_ROOT=$SCRATCH/vista_build \
#PLATFORM_LABEL=Vista \
#MODULE_NCARENV="" \
#MODULE_GCC="gcc/14.2.0" \
#MODULE_HDF5="phdf5/1.14.6" \
#MODULE_CMAKE="cmake/4.1.1" \
#MODULE_MPI="openmpi/5.0.11" \
#MODULE_NETCDF="parallelnetcdf/4.9.2" \
#./HESM-S2S/envs/build_parallelio.sh

# FMS
INSTALL_ROOT=$WORK/envs \
BUILD_DIR_ROOT=$SCRATCH/vista_build \
PLATFORM_LABEL=Vista \
MODULE_NCARENV="" \
MODULE_GCC="gcc/14.2.0" \
MODULE_HDF5="phdf5/1.14.6" \
MODULE_CMAKE="cmake/4.1.1" \
MODULE_MPI="openmpi/5.0.11" \
MODULE_NETCDF="parallelnetcdf/4.9.2" \
./HESM-S2S/envs/build_fms.sh

# MPI4py
LDSHARED="$OMPI/bin/mpicc -shared -Wl,-rpath,$OMPI/lib" \
MPI4PY_VERSION=4.1.2 \
INSTALL_ROOT=$WORK/envs \
BUILD_DIR_ROOT=$SCRATCH/vista_build \
PLATFORM_LABEL=Vista \
MODULE_NCARENV="" \
MODULE_GCC="gcc/14.2.0" \
MODULE_MPI="openmpi/5.0.11" \
MPICC_WRAPPER=/opt/apps/gcc14/openmpi/5.0.11/bin/mpicc \
PYTHON_ENV=$WORK/envs/hybrid-s2s \
./HESM-S2S/envs/build_mpi4py.sh

# CONDUIT
INSTALL_ROOT=$WORK/envs \
BUILD_DIR_ROOT=$SCRATCH/vista_build \
PLATFORM_LABEL=Vista \
OMPI=/opt/apps/gcc14/openmpi/5.0.11 \
MODULE_NCARENV="" \
MODULE_GCC=gcc/14.2.0 \
MODULE_MPI=openmpi/5.0.11 \
MODULE_CMAKE=cmake/4.1.1 \
MPICC_WRAPPER=$OMPI/bin/mpicc \
MPICXX_WRAPPER=$OMPI/bin/mpicxx \
MPIF90_WRAPPER=$OMPI/bin/mpif90 \
PYTHON_ENV=$WORK/envs/hybrid-s2s \
./HESM-S2S/envs/build_conduit.sh

# ESMF
module use -a $WORK/envs/modulefiles
module load parallelio/2.6.6

INSTALL_ROOT=$WORK/envs \
BUILD_DIR_ROOT=$SCRATCH/vista_build \
PLATFORM_LABEL=Vista \
OMPI=/opt/apps/gcc14/openmpi/5.0.11 \
ESMF_F90LINKLIBS="-lm" \
PIO_C_INCLUDE_DIR=$WORK/envs/parallelio/2.6.6/include \
PIO_C_LIBRARY=$WORK/envs/parallelio/2.6.6/lib \
MODULE_NCARENV=TACC \
MODULE_GCC=gcc/14.2.0 \
MODULE_MPI=openmpi/5.0.11 \
MODULE_CMAKE=cmake/4.1.1 \
MODULE_HDF5=phdf5/1.14.6 \
MODULE_NETCDF=parallelnetcdf/4.9.2 \
MODULE_PIO="parallelio/2.6.6" \
MPICC_WRAPPER=$OMPI/bin/mpicc \
MPICXX_WRAPPER=$OMPI/bin/mpicxx \
MPIF90_WRAPPER=$OMPI/bin/mpif90 \
./HESM-S2S/envs/build_esmf.sh
