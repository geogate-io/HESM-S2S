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

PYTHON_ENV=/glade/work/turuncu/ML-2.0/envs/aurora
# Plain PATH/LD_LIBRARY_PATH prepend rather than `module load conda` +
# `conda activate`: Lmod's conda module conflicts with the `python`
# module already loaded above (pulled in by esmf/paraview's own spack
# stack), and conda activate needs `conda init` to have run in this
# shell anyway. Python doesn't need conda's shell machinery to find its
# own site-packages -- that's derived from the interpreter's own install
# path -- so putting this env's bin first on PATH is enough.
export PATH=${PYTHON_ENV}/bin:${PATH}
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

module use -a /glade/work/epicufsrt/contrib/spack-stack/derecho/spack-stack-1.9.2/envs/ue-gcc-12.2.0/install/modulefiles/cray-mpich/8.1.27-swca2sj/gcc/12.2.0/
module load fms/2024.02
module li
