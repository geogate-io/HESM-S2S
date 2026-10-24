#!/bin/bash

module --force purge

module load TACC
module load ucc/1.9.0
module load ucx/1.22.0
module load xalt/3.1
module load gcc/14.2.0
module load openmpi/5.0.5
module load nvpl/26.9
module load cmake/4.1.1
module load phdf5/1.14.6
module load parallelnetcdf/4.9.2

module use -a /work/01118/tg803972/vista/envs/modulefiles
module load fms/2024.02
module load parallelio/2.6.6
module load esmf-mpi/8.9.0
module load conduit/0.9.2

PYTHON_ENV=$WORK/envs/hybrid-s2s
export PATH=${PYTHON_ENV}/bin:${PATH}
export LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:${PYTHON_ENV}/lib
export PYTHONPATH=${CONDUIT_ROOT}/python-modules:${PYTHONPATH}
export LD_LIBRARY_PATH=${TACC_HDF5_DIR}/lib:${LD_LIBRARY_PATH}
export NETCDF_INCDIR=${TACC_PARALLELNETCDF_BIN}/include
export NETCDF_LIBDIR=${TACC_PARALLELNETCDF_BIN}/lib64
export PIO_C_PATH=${parallelio_ROOT}
export PIO_Fortran_PATH=${parallelio_ROOT}
export PIO_C_LIBRARY=${PIO_C_PATH}/lib
export PIO_C_INCLUDE_DIR=${PIO_C_PATH}/include
export PIO_Fortran_LIBRARY=${PIO_Fortran_PATH}/lib
export PIO_Fortran_INCLUDE_DIR=${PIO_Fortran_PATH}/include
