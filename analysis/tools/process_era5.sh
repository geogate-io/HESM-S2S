#!/bin/bash

module load nco
module load cdo

input="era5_00_06_12_18.nc"

#for d in "2021-01-01T03:00:00" "2021-04-01T03:00:00" "2021-07-01T03:00:00" "2021-10-01T03:00:00"
for d in "2021-01-01T00:00:00" "2021-04-01T00:00:00" "2021-07-01T00:00:00" "2021-10-01T00:00:00"
do
  # information
  lns=`cdo -w showtimestamp $input | tr ' ' '\n' | sort | awk 'NF' | grep -n "$d" | awk -F: '{print $1}'`
  #lne=$((lns+139))
  lne=$((lns+140))
  out_dir=`echo $d | awk -FT '{print $1}' | tr -d "-"`
  out_dir="${out_dir}_era5"
  echo $d $lns $lne $out_dir

  # create directory
  if [ ! -d "$out_dir" ]; then
    mkdir $out_dir
  fi

  # split first 35d
  ncks -d valid_time,$((lns-1)),$((lne-1)) $input $out_dir/era5_35d.nc

  # 6h 0,6,12,18 -> 3h -> 6h 3,9,15,21
  #cdo inttime,${d/T/,},3hour $out_dir/era5_35d.nc $out_dir/era5_35d_3h.nc
  #cdo selhour,3,9,15,21 $out_dir/era5_35d_3h.nc $out_dir/era5_35d.nc

  # calculate temporal averages
  cdo daymean $out_dir/era5_35d.nc $out_dir/era5_35d_daily.nc
  cdo timmean $out_dir/era5_35d.nc $out_dir/era5_35d_tmean.nc
done
