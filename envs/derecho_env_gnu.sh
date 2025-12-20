#!/bin/bash

module --force purge

module load ncarenv/23.09
module load gcc/12.2.0
module load cray-mpich/8.1.27
module load craype/2.7.31

module use -a /glade/work/turuncu/ML/envs/spack-1.0.2/var/spack/environments/myenv/install/modulefiles/Core
module use -a /glade/work/turuncu/ML/envs/spack-1.0.2/var/spack/environments/myenv/install/modulefiles/cray-mpich/8.1.27-6ikx5ff/Core

module load cmake/3.31.8
module load esmf/8.9.0
module load paraview/5.13.3
module load conduit/0.9.2
module load libcatalyst/2.0.0

PYTHON_ENV=/glade/work/turuncu/ML/envs/earth2studio
export LD_LIBRARY_PATH=${PYTHON_ENV}/lib:${LD_LIBRARY_PATH}
export LD_LIBRARY_PATH=${HDF5_ROOT}/lib:${LD_LIBRARY_PATH}
export NETCDF_INCDIR=${NETCDF_FORTRAN_ROOT}/include
export NETCDF_LIBDIR=${NETCDF_FORTRAN_ROOT}/lib
export PIO_C_PATH=${PARALLELIO_ROOT}
export PIO_Fortran_PATH=${PARALLELIO_ROOT}
export PIO_C_LIBRARY=${PIO_C_PATH}/lib
export PIO_C_INCLUDE_DIR=${PIO_C_PATH}/include
export PIO_Fortran_LIBRARY=${PIO_Fortran_PATH}/lib
export PIO_Fortran_INCLUDE_DIR=${PIO_Fortran_PATH}/include
module li
