#!/bin/bash

module load nco
module load cdo

input="oisst-avhrr-v02r01_2021.nc"

for d in "2021-01-01T12:00:00" "2021-04-01T12:00:00" "2021-07-01T12:00:00" "2021-10-01T12:00:00"
do
  # information
  lns=`cdo -w showtimestamp $input | tr ' ' '\n' | sort | awk 'NF' | grep -n "$d" | awk -F: '{print $1}'`
  lne=$((lns+34))
  out_dir=`echo $d | awk -FT '{print $1}' | tr -d "-"`
  out_dir="${out_dir}_oisst"
  echo $d $lns $lne $out_dir

  # create directory
  if [ ! -d "$out_dir" ]; then
    mkdir $out_dir
  fi

  # split first 35d
  ncks -d time,$((lns-1)),$((lne-1)) $input $out_dir/oisst_35d.nc

  # remap to ERA5 grid
  cdo remapbil,grid_era5.txt $out_dir/oisst_35d.nc $out_dir/oisst_35d_remap_bil.nc

  # calculate temporal averages
  cdo timmean $out_dir/oisst_35d_remap_bil.nc $out_dir/oisst_35d_remap_bil_tmean.nc
done
