#!/bin/bash

module load nco
module load cdo

for out_dir in "20210101_ssh" "20210401_ssh" "20210701_ssh" "20211001_ssh"
do
  echo $out_dir

  # remap to ERA5 grid
  cdo remapbil,grid_era5.txt $out_dir/ssh_35d.nc $out_dir/ssh_35d_remap_bil.nc

  # calculate temporal averages
  cdo timmean $out_dir/ssh_35d_remap_bil.nc $out_dir/ssh_35d_remap_bil_tmean.nc
done
