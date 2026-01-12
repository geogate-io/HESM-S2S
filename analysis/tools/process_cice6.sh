#!/bin/bash

module load nco
module load cdo

for d in `ls -ald ../2021* | awk '{print $9}'`
do
  echo "processing $d"

  # create directory
  out_dir=`basename $d`
  if [ ! -d "$out_dir" ]; then
    mkdir $out_dir
  fi

  # extract subset of variables
  olst=""
  lst=`ls -al $d/history/iceh.*.nc | awk '{print $9}'`
  for f in $lst
  do
    ofile="$out_dir/`basename $f`"
    ofile=${ofile/.nc/_sub.nc}
    echo $ofile
    len=`ncdump -c  $f | grep "time = UNLIMITED" | awk '{print $6}' | tr -d "("`
    if [ "$len" == "1" ]; then
      echo $f $ofile
      ncks -O -v aice_d,hi_d,tarea,TLAT,TLON $f $ofile
      olst="$olst $ofile"
    fi
  done

  # merge files
  ncrcat -O $olst $out_dir/ice_merged_35d.nc
  rm -f $olst

  # remap to ERA5 grid
  cdo remapbil,grid_era5.txt $out_dir/ice_merged_35d.nc $out_dir/ice_merged_35d_remap_bil.nc

  # calculate temporal averages
  cdo daymean $out_dir/ice_merged_35d_remap_bil.nc $out_dir/ice_merged_35d_remap_bil_daily.nc
  cdo timmean $out_dir/ice_merged_35d_remap_bil.nc $out_dir/ice_merged_35d_remap_bil_tmean.nc
done
