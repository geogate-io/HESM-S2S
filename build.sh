#!/bin/bash
# Main script to build application DLROMS: [CDEPS, GeoGate, MOM6, CICE6, CMEPS]
# -DDEBUG=ON can be passed to GeoGate build_args to enable debugging
#
# Usage: ./build.sh [derecho|casper]   (default: derecho)
set -euo pipefail

PLATFORM=${1:-derecho}
case "${PLATFORM}" in
  derecho|casper) ;;
  *)
    echo "Usage: $0 [derecho|casper]" >&2
    exit 1
    ;;
esac

echo "Building for platform: ${PLATFORM}"

# Load environment
source envs/${PLATFORM}_env_gnu.sh

# Clean old build
rm -rf build install esmxBuild.yaml

# Path for FMS build
FMS_ROOT=$fms_ROOT
echo $FMS_ROOT

# Path to libpython*.so for the geogate link step, derived from whichever
# python3 envs/${PLATFORM}_env_gnu.sh put on PATH (PYTHON_ENV), rather than
# hardcoding it -- same query GeoGate/Conduit's own SetupPython.cmake uses.
PYTHON_LIBDIR=$(python3 -c "from sysconfig import get_config_var; print(get_config_var('LIBDIR'))")
echo $PYTHON_LIBDIR

# Create esmxBuild.yaml
echo "application:" >> esmxBuild.yaml 
echo "  disable_comps: ESMX_Data" >> esmxBuild.yaml
echo "  link_libraries: piof" >> esmxBuild.yaml
echo "components:" >> esmxBuild.yaml
echo "  datm:" >> esmxBuild.yaml
echo "    source_dir: src/CDEPS" >> esmxBuild.yaml
echo "    build_type: cmake.external" >> esmxBuild.yaml
echo "    build_args: \"-DDISABLE_FoX=ON -DCPRGNU=ON -DPIO_C_LIBRARY=$PIO_C_LIBRARY -DPIO_C_INCLUDE_DIR=$PIO_C_INCLUDE_DIR -DPIO_Fortran_LIBRARY=$PIO_Fortran_LIBRARY -DPIO_Fortran_INCLUDE_DIR=$PIO_Fortran_INCLUDE_DIR -DCMAKE_Fortran_FLAGS=-ffree-line-length-none\"" >> esmxBuild.yaml
echo "    fort_module: cdeps_datm_comp.mod" >> esmxBuild.yaml
echo "    libraries: datm dshr streams cdeps_share" >> esmxBuild.yaml
echo "  cice6:" >> esmxBuild.yaml
echo "    source_dir: src/CICE_interface" >> esmxBuild.yaml
echo "    build_type: cmake.external" >> esmxBuild.yaml
echo "    build_args: \"-DCICE_IO=NetCDF -DCMAKE_Fortran_FLAGS=-I${PWD}/build/datm/share\"" >> esmxBuild.yaml
echo "    fort_module: ice_comp_nuopc" >> esmxBuild.yaml
echo "    libraries: cice" >> esmxBuild.yaml
echo "  geogate:" >> esmxBuild.yaml
echo "    source_dir: src/GeoGate/src" >> esmxBuild.yaml
echo "    build_type: cmake.external" >> esmxBuild.yaml
echo "    build_args: \"-DGEOGATE_USE_PYTHON=ON -DCMAKE_Fortran_FLAGS=-ffree-line-length-none\"" >> esmxBuild.yaml
echo "    fort_module: geogate_nuopc.mod" >> esmxBuild.yaml
echo "    libraries: geogate geogate_io geogate_python geogate_catalyst geogate_shared" >> esmxBuild.yaml
echo "    link_paths: ${PYTHON_LIBDIR}" >> esmxBuild.yaml
echo "    link_libraries: conduit python3.12" >> esmxBuild.yaml
echo "  mom6:" >> esmxBuild.yaml
echo "    source_dir: src/MOM6_interface" >> esmxBuild.yaml
echo "    build_type: cmake.external" >> esmxBuild.yaml
echo "    fort_module: mom_cap_mod" >> esmxBuild.yaml
echo "    libraries: mom6" >> esmxBuild.yaml
echo "    link_paths: $FMS_ROOT" >> esmxBuild.yaml
echo "    link_libraries: fms_r8 cdeps_share" >> esmxBuild.yaml
echo "  cmeps:" >> esmxBuild.yaml
echo "    source_dir: src/CMEPS" >> esmxBuild.yaml
echo "    build_type: cmake.external" >> esmxBuild.yaml
echo "    build_args: \"-DPIO_C_LIBRARY=$PIO_C_LIBRARY -DPIO_C_INCLUDE_DIR=$PIO_C_INCLUDE_DIR -DPIO_Fortran_LIBRARY=$PIO_Fortran_LIBRARY -DPIO_Fortran_INCLUDE_DIR=$PIO_Fortran_INCLUDE_DIR -DCMAKE_Fortran_FLAGS=-I${PWD}/build/datm/share\"" >> esmxBuild.yaml
echo "    fort_module: med.mod" >> esmxBuild.yaml
echo "    libraries: cmeps cmeps_share" >> esmxBuild.yaml

# Build application
ESMX_Builder -v --build-jobs=4 --cmake-args="-DCMAKE_Fortran_FLAGS=-I${PWD}/build/cmeps/mediator"
