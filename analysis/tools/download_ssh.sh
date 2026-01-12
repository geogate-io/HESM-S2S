#!/bin/bash

copernicusmarine subset \
   --dataset-id cmems_obs-sl_glo_phy-ssh_my_allsat-l4-duacs-0.125deg_P1D \
   --variable adt \
   --variable flag_ice \
   --variable sla \
   --start-datetime 2021-10-01T00:00:00 \
   --end-datetime 2021-11-04T00:00:00 \
   --minimum-longitude -179.9375 \
   --maximum-longitude 179.9375 \
   --minimum-latitude -89.9375 \
   --maximum-latitude 89.9375

# Jan
#   --start-datetime 2021-01-01T00:00:00 \
#   --end-datetime 2021-02-04T00:00:00 \
# Apr
#   --start-datetime 2021-04-01T00:00:00 \
#   --end-datetime 2021-05-05T00:00:00 \
# Jul
#   --start-datetime 2021-07-01T00:00:00 \
#   --end-datetime 2021-08-04T00:00:00 \
# Oct
#   --start-datetime 2021-10-01T00:00:00 \
#   --end-datetime 2021-11-04T00:00:00 \
