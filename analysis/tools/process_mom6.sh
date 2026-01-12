#!/bin/bash

module load nco
module load cdo

for d in `ls -ald ../2021* | awk '{print $9}' | grep 20210101_aurora`
do
  echo "processing $d"

  # create directory
  out_dir=`basename $d`
  if [ ! -d "$out_dir" ]; then
    mkdir $out_dir
  fi

  # extract subset of variables
  olst=""
  lst=`ls -al $d/MOM6_OUTPUT/ocn_*.nc | awk '{print $9}'`
  for f in $lst
  do
    ofile="$out_dir/`basename $f`"
    ofile=${ofile/.nc/_sub.nc}
    echo $ofile
    len=`ncdump -c  $f | grep "time = UNLIMITED" | awk '{print $6}' | tr -d "("`
    if [ "$len" == "1" ]; then
      echo $f $ofile
      ncks -O -v SST,SSH,latent,sensible,LW,SW,LwLatSens,Heat_PmE,geolon,geolat $f $ofile
      olst="$olst $ofile"
    fi
  done

  # merge files
  ncrcat -O $olst $out_dir/ocn_merged.nc
  rm -f $olst

  # split first 35d, 6-hourly
  ncks -d time,0,139 $out_dir/ocn_merged.nc $out_dir/ocn_merged_35d.nc

  # remap to ERA5 grid
  cdo remapbil,grid_era5.txt $out_dir/ocn_merged_35d.nc $out_dir/ocn_merged_35d_remap_bil.nc
  cdo remapcon,grid_era5.txt $out_dir/ocn_merged_35d.nc $out_dir/ocn_merged_35d_remap_con.nc

  # calculate temporal averages
  cdo daymean $out_dir/ocn_merged_35d_remap_bil.nc $out_dir/ocn_merged_35d_remap_bil_daily.nc
  cdo daymean $out_dir/ocn_merged_35d_remap_con.nc $out_dir/ocn_merged_35d_remap_con_daily.nc 
  cdo timmean $out_dir/ocn_merged_35d_remap_bil.nc $out_dir/ocn_merged_35d_remap_bil_tmean.nc
  cdo timmean $out_dir/ocn_merged_35d_remap_con.nc $out_dir/ocn_merged_35d_remap_con_tmean.nc 
done
