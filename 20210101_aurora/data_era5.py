import sys
from conduit import Node
import numpy as np
import xarray as xr

# Arguments
state = "export"
channel = "atm"
nx_atm = 1440
ny_atm = 721
debug = False 
log = False 

# Query time string
tstr = my_node['state/time_str']

# Access to channel
my_channel = my_node["channels/{}/{}".format(state, channel)]

# Save the data in the channel
if debug:
    my_channel.save('my_channel_{}_{}_{}'.format(state, channel, tstr))

# Read data from file, returns nearest time in coupling time step is smaller than data's temporal resolution
ds_msl = xr.open_dataset("/glade/derecho/scratch/turuncu/data/Data_mom6/data_msl_2021_merged.nc", engine="netcdf4").sel(time=tstr, method="nearest")
ds_t2m = xr.open_dataset("/glade/derecho/scratch/turuncu/data/Data_mom6/data_t2m_2021_merged.nc", engine="netcdf4").sel(time=tstr, method="nearest")
ds_q2  = xr.open_dataset("/glade/derecho/scratch/turuncu/data/Data_mom6/data_q2_2021_merged.nc", engine="netcdf4").sel(time=tstr, method="nearest")
ds_tp  = xr.open_dataset("/glade/derecho/scratch/turuncu/data/Data_mom6/data_tp_2021_merged.nc", engine="netcdf4").sel(time=tstr, method="nearest")
ds_u10 = xr.open_dataset("/glade/derecho/scratch/turuncu/data/Data_mom6/data_u10_2021_merged.nc", engine="netcdf4").sel(time=tstr, method="nearest")
ds_v10 = xr.open_dataset("/glade/derecho/scratch/turuncu/data/Data_mom6/data_v10_2021_merged.nc", engine="netcdf4").sel(time=tstr, method="nearest")
ds_strd= xr.open_dataset("/glade/derecho/scratch/turuncu/data/Data_mom6/data_strd_2021_merged.nc", engine="netcdf4").sel(time=tstr, method="nearest")
ds_ssrd= xr.open_dataset("/glade/derecho/scratch/turuncu/data/Data_mom6/data_ssrd_2021_merged.nc", engine="netcdf4").sel(time=tstr, method="nearest")
ds = xr.merge([ds_msl, ds_t2m, ds_q2, ds_tp, ds_u10, ds_v10, ds_strd, ds_ssrd], compat='override').drop_vars(["time"])

# Apply unit conversions
ds['tp'] = ds['tp']/3600.0*1000.0 # m/s to kg/m^2/s
ds['strd'] = ds['strd']/3600.0 # J/m2 -> W/m2
ds['ssrd'] = ds['ssrd']/3600.0 # J/m2 -> W/m2

# Add new variables, shortwave in bands (required for ice model)
ds["swvdr"] = ds['ssrd']*0.28 # W/m2
ds["swndr"] = ds['ssrd']*0.31 # W/m2
ds["swvdf"] = ds['ssrd']*0.24 # W/m2
ds["swndf"] = ds['ssrd']*0.17 # W/m2

# Data is converted to double since GeoGate Conduit interface is designed to expect double
# GeoGate TODO: Allow other data types without type conversion
for var in ds.data_vars:
    if np.issubdtype(ds[var].dtype, np.number):
        ds[var] = ds[var].astype(np.float64)

# Redirect stdout
if log:
    with open('output_{}.txt'.format(tstr), 'w') as f:
        sys.stdout = f
        print("Time = {}".format(tstr))
        for vn, da in ds.data_vars.items():
            print(f"{vn} min, max = {da.min().item():.3f}, {da.max().item():.3f}")
        
# Save data for debugging
if debug:
    ds.to_netcdf("data_{}_{}_{}.nc".format(state, channel, tstr), engine='netcdf4')

# Return new node with modified data
my_node_return = Node()
my_node_return.update(my_channel)
my_node_return['data/fields/Sa_z/values']       = ds['u10'].values.reshape(-1)*0.0+10.0 # m, constant
my_node_return['data/fields/Sa_u10m/values']    = ds['u10'].values.reshape(-1) # m/s
my_node_return['data/fields/Sa_v10m/values']    = ds['v10'].values.reshape(-1) # m/s
my_node_return['data/fields/Sa_u/values']       = ds['u10'].values.reshape(-1) # m/s
my_node_return['data/fields/Sa_v/values']       = ds['v10'].values.reshape(-1) # m/s
my_node_return['data/fields/Sa_pslv/values']    = ds['msl'].values.reshape(-1) # Pa
my_node_return['data/fields/Sa_pbot/values']    = ds['msl'].values.reshape(-1) # Pa
my_node_return['data/fields/Sa_t2m/values']     = ds['t2m'].values.reshape(-1) # K
my_node_return['data/fields/Sa_tbot/values']    = ds['t2m'].values.reshape(-1) # K
my_node_return['data/fields/Sa_q2m/values']     = ds['q2'].values.reshape(-1) # kg/kg
my_node_return['data/fields/Sa_shum/values']    = ds['q2'].values.reshape(-1) # kg/kg
my_node_return['data/fields/Faxa_rain/values']  = ds['tp'].values.reshape(-1) # kg/m^2/s
my_node_return['data/fields/Faxa_lwdn/values']  = ds['strd'].values.reshape(-1) # W/m2
my_node_return['data/fields/Faxa_swdn/values']  = ds['ssrd'].values.reshape(-1) # W/m2
my_node_return['data/fields/Faxa_swvdr/values'] = ds['swvdr'].values.reshape(-1) # W/m2
my_node_return['data/fields/Faxa_swndr/values'] = ds['swndr'].values.reshape(-1) # W/m2
my_node_return['data/fields/Faxa_swvdf/values'] = ds['swvdf'].values.reshape(-1) # W/m2
my_node_return['data/fields/Faxa_swndf/values'] = ds['swndf'].values.reshape(-1) # W/m2
if debug:
    my_node_return.save('my_node_return_{}_{}_{}'.format(state, channel, tstr))
