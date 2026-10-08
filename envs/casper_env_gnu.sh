#!/bin/bash
# Casper port of derecho_env_gnu.sh
#
# Derecho's build used a user-built Spack stack (gcc/12.2.0 + cray-mpich,
# installed under /glade/work/turuncu/ML/envs/spack-1.0.2) plus the
# epicufsrt spack-stack-1.9.2 module tree for FMS. None of that is usable
# on Casper: it is a Cray-MPICH build tagged for the Derecho "zen3" CPU
# target, and epicufsrt's spack-stack has no Casper variant anymore.
#
# Casper has its own native module tree (ncarenv/25.10) that natively
# provides a matching gcc + openmpi + esmf/netcdf/hdf5/parallelio stack,
# so this script uses that instead of a custom Spack environment.
#
# Known gaps vs. derecho_env_gnu.sh:
#   - FMS (fms/2024.02 on derecho) and Conduit (conduit/0.9.2 on derecho,
#     needed only by GeoGate's GEOGATE_USE_PYTHON plugin) have no Casper
#     module. Run envs/casper_build_fms.sh and envs/casper_build_conduit.sh
#     once to build both and generate the Lmod modules loaded below.
#   - Catalyst/libcatalyst and ParaView are intentionally dropped: build.sh
#     must be run with -DGEOGATE_USE_CATALYST=OFF on Casper.

module --force purge

module load ncarenv/25.10
module load gcc/14.3.0
module load openmpi/5.0.8

module load cmake/3.31.8
module load hdf5-mpi/1.14.6
module load netcdf-mpi/4.9.3
module load parallelio/2.6.6
module load esmf-mpi/8.9.0

# FMS and Conduit: built from source by casper_build_fms.sh /
# casper_build_conduit.sh (no Casper module for either exists upstream).
# These module() calls fail loudly if the builds haven't been run yet.
module use -a /glade/work/turuncu/ML-2.0/envs/casper/modulefiles
module load fms/2024.02
module load conduit/0.9.2

PYTHON_ENV=/glade/work/turuncu/ML-2.0/envs/aurora
# Same reasoning as derecho_env_gnu.sh: a plain PATH/LD_LIBRARY_PATH
# prepend is enough since this env's own install path carries its
# site-packages -- no need for `module load conda` / `conda activate`.
export PATH=${PYTHON_ENV}/bin:${PATH}
export LD_LIBRARY_PATH=${PYTHON_ENV}/lib:${LD_LIBRARY_PATH}
export LD_LIBRARY_PATH=${NCAR_ROOT_HDF5}/lib:${LD_LIBRARY_PATH}

# Casper's netcdf-mpi module bundles netcdf-c and netcdf-fortran together
# (no separate NETCDF_FORTRAN_ROOT like on derecho).
export NETCDF_INCDIR=${NCAR_ROOT_NETCDF}/include
export NETCDF_LIBDIR=${NCAR_ROOT_NETCDF}/lib

export PIO_C_PATH=${NCAR_ROOT_PARALLELIO}
export PIO_Fortran_PATH=${NCAR_ROOT_PARALLELIO}
export PIO_C_LIBRARY=${PIO_C_PATH}/lib
export PIO_C_INCLUDE_DIR=${PIO_C_PATH}/include
export PIO_Fortran_LIBRARY=${PIO_Fortran_PATH}/lib
export PIO_Fortran_INCLUDE_DIR=${PIO_Fortran_PATH}/include

# fms_ROOT and CONDUIT_ROOT come from the fms/conduit modules loaded above.
module li
