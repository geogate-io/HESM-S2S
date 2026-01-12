#!/bin/bash
module load nco

year=2021
lst=""
for mm in `seq -w 1 12`
do
  ndays=$(date -d "$year-$mm-01 +1 month -1 day" +"%d")
  for dd in `seq -w 1 $ndays`
  do
    echo $year $mm $dd
    wget -c https://www.ncei.noaa.gov/data/sea-surface-temperature-optimum-interpolation/v2.1/access/avhrr/${year}${mm}/oisst-avhrr-v02r01.${year}${mm}${dd}.nc
    lst="$lst oisst-avhrr-v02r01.${year}${mm}${dd}.nc"
  done
done

ncrcat $lst oisst-avhrr-v02r01_2021.nc
