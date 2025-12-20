#!/bin/bash
# Main script to build application DLROMS: [CDEPS, GeoGate, ROMS]
# -DDEBUG=ON can be passed to GeoGate build_args to enable debugging

# Load environment
source envs/derecho_env_gnu.sh

# Clean old build
rm -rf build install esmxBuild.yaml

# Path for FMS build
FMS_ROOT="/glade/work/turuncu/ML/runs/cmom.jra.gnu/bld"

# Create esmxBuild.yaml
echo "application:" >> esmxBuild.yaml 
echo "  disable_comps: ESMX_Data" >> esmxBuild.yaml
echo "  link_libraries: piof" >> esmxBuild.yaml
#echo "  link_libraries: piof conduit catalyst catalyst_fortran python3.12" >> esmxBuild.yaml
echo "components:" >> esmxBuild.yaml
echo "  datm:" >> esmxBuild.yaml
echo "    source_dir: src/CDEPS" >> esmxBuild.yaml
echo "    build_type: cmake.external" >> esmxBuild.yaml
echo "    build_args: \"-DDISABLE_FoX=ON -DCPRGNU=ON -DPIO_C_LIBRARY=$PIO_C_LIBRARY -DPIO_C_INCLUDE_DIR=$PIO_C_INCLUDE_DIR -DPIO_Fortran_LIBRARY=$PIO_Fortran_LIBRARY -DPIO_Fortran_INCLUDE_DIR=$PIO_Fortran_INCLUDE_DIR -DCMAKE_Fortran_FLAGS=-ffree-line-length-none\"" >> esmxBuild.yaml
echo "    fort_module: cdeps_datm_comp.mod" >> esmxBuild.yaml
echo "    libraries: datm dshr streams cdeps_share" >> esmxBuild.yaml
echo "  geogate:" >> esmxBuild.yaml
echo "    source_dir: src/GeoGate/src" >> esmxBuild.yaml
echo "    build_type: cmake.external" >> esmxBuild.yaml
echo "    build_args: \"-DGEOGATE_USE_PYTHON=ON -DGEOGATE_USE_CATALYST=ON -DCMAKE_Fortran_FLAGS=-ffree-line-length-none\"" >> esmxBuild.yaml
echo "    fort_module: geogate_nuopc.mod" >> esmxBuild.yaml
echo "    libraries: geogate geogate_io geogate_python geogate_catalyst geogate_shared" >> esmxBuild.yaml
echo "    link_libraries: conduit catalyst catalyst_fortran python3.12" >> esmxBuild.yaml
echo "  mom6:" >> esmxBuild.yaml
echo "    source_dir: src/MOM6_interface" >> esmxBuild.yaml
echo "    build_type: cmake.external" >> esmxBuild.yaml
echo "    fort_module: mom_cap_mod" >> esmxBuild.yaml
echo "    libraries: mom6" >> esmxBuild.yaml
echo "    link_paths: $FMS_ROOT/lib $FMS_ROOT/gnu/mpich/nodebug/nothreads/csm_share" >> esmxBuild.yaml
echo "    link_libraries: fms csm_share" >> esmxBuild.yaml

# Build application
ESMX_Builder -v --build-jobs=4
