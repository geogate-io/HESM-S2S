
import os
import sys
import numpy as np
import xarray as xr
import pandas as pd
from datetime import datetime, timedelta
from conduit import Node

# Functions
def find_closest_6h_interval(time):
    """
    Find the closest 6-hour interval bounds for a given time.
    """
    # Find distance based on midnight
    seconds_since_midnight = (
        time - time.replace(hour=0, minute=0, second=0, microsecond=0)
    ).total_seconds()
    interval_seconds = 6 * 3600
    floor_intervals = int(seconds_since_midnight / interval_seconds)
    ceil_intervals = floor_intervals + 1

    # Find lower and upper time
    floor_time = time.replace(hour=0, minute=0, second=0, microsecond=0)+timedelta(seconds=floor_intervals * interval_seconds)
    ceil_time = time.replace(hour=0, minute=0, second=0, microsecond=0)+timedelta(seconds=ceil_intervals * interval_seconds)

    # Return bound
    return [floor_time, ceil_time]

if __name__ == "__main__":
    # Arguments
    nx_atm = 1440
    ny_atm = 721 # south pole is added to prediction
    debug = False 
    output_path = './predictions'
    perform_temporal_interpolation = True 
    temporal_interpolation_method = "linear"
    has_import = True # enable two-way coupling and feedback from ocean to atmosphere

    # Output file path if it does not exist
    if not os.path.exists(output_path):
        os.makedirs(output_path, exist_ok=True)

    # Set epoch date
    epoch_date = pd.Timestamp("1970-01-01")

    # Access to channel
    # Ocean model data on atmospheric model grid/mesh for "import_on_export_grid"
    # Use "import" to access data on the ocean model grid/mesh
    my_channel_atm = my_node["channels/{}/{}".format("export", "atm")]
    my_channel_ocn = my_node["channels/{}/{}".format("import_on_export_grid", "ocn")]
    model_time_str = my_node['state/time_str'] # e.g., "2011-08-27T06:00:00"
    model_time = datetime.strptime(model_time_str, "%Y-%m-%dT%H:%M:%S")

    # Find lower and upper bound or requested time
    time_lb, time_ub = find_closest_6h_interval(model_time)
    print(f"Model time: {model_time}, closest 6h interval: {time_lb.strftime('%Y-%m-%dT%H:%M:%S')} - {time_ub.strftime('%Y-%m-%dT%H:%M:%S')}", flush=True)

    # Set forecast time
    time_delta = 6 # hours
    if model_time == time_lb:
        forecast_time = time_lb
    else:
        forecast_time = time_ub
    forecast_time_str = forecast_time.strftime("%Y-%m-%dT%H:%M:%S")

    # Start and end date for data loading, need to cover t-6h, t and t+6h
    duration = timedelta(hours=time_delta)
    start_date = (forecast_time - 2*duration).strftime("%Y-%m-%dT%H:%M:%S")
    end_date =  (forecast_time - duration).strftime("%Y-%m-%dT%H:%M:%S")
    print(f"Forecast time: {forecast_time} (inputs -> t-6h: {start_date}, t: {end_date})", flush=True)

    # Set output file name
    ofile = os.path.join(output_path, f"pred_{forecast_time_str}.nc")

    # Check if prediction output file already exists or not, if it exists we can skip prediction and load existing file, otherwise we need to make new prediction
    if os.path.exists(ofile):
        print(f"Prediction output file {ofile} already exists, skipping prediction.", flush=True)

        # Load existing dataset
        ds = xr.open_dataset(ofile, engine="netcdf4")
    else:
        # Import required modules to make new prediction
        import time
        import yaml
        import torch
        from torch.utils.data import DataLoader
        from aurora import rollout
        from aurora import AuroraPretrained
        from aurora import Batch, Metadata
        from aurora.normalisation import locations, scales
        from data_aurora_utils_v2 import AuroraDataset, batch_collate_fn, batch_to_dataset, _np

        # Print forecast time
        print(f"Making prediction for forecast time: {forecast_time_str}", flush=True)

        # Load config from YAML file
        with open("config.yaml", "r") as f:
            settings = yaml.safe_load(f)
        generic_settings = settings["aurora_config"]["generic"]
        prediction_settings = settings["aurora_config"]["prediction"]

        # Variables downloaded from (ECMWF's cds.climate.copernicus.eu)
        # lat = 90 to -90 (721 points)
        # lon = 0 to 359.75 (1440 points)
        # lev = 1000, 925, 850, 700, 600, 500, 400, 300, 250, 200, 150, 100, 50
        variables = {
            "surf": {
                "2t" : "t2m",
                "10u": "u10",
                "10v": "v10",
                "msl": "msl",
            },
            "static": {
                "z"  : "hgt",
                "slt": "slt",
                "lsm": "lsm"
            },
            "atmos": {
                "t"  : "t",
                "u"  : "u",
                "v"  : "v",
                "q"  : "q",
                "z"  : "z"
            }
        }

        # Include additional surface variables
        if "new_surf_vars" in generic_settings and generic_settings["new_surf_vars"] is not None:
            for key, val in generic_settings["new_surf_vars"].items():
                variables["surf"][key] = val["name"]

        # List of variables
        surf_vars = tuple(variables["surf"].keys())
        static_vars = tuple(variables["static"].keys())
        atmos_vars = tuple(variables["atmos"].keys())

        # Set device
        device_type = torch.accelerator.current_accelerator()
        device = torch.device(f"{device_type}")

        # Initialize model
        model = AuroraPretrained(
            surf_vars=surf_vars,
            static_vars=static_vars,
            atmos_vars=atmos_vars
        )

        # Load pretrained weights
        model.load_checkpoint_local(prediction_settings["checkpoint_file"], strict=False)

        # Set model to evaluation mode
        model.eval()

        # Move model to device
        model.to(device)

        # Prepare Aurora dataset for the given time range
        data_path = generic_settings["data_path"]
        if has_import:
            print("*** Two-way coupling enabled ***", flush=True)

            # Get variable and land-sea mask on atmospheric model grid/mesh from the channel
            sst = my_channel_ocn['data/fields/So_t/values'].reshape((ny_atm,nx_atm))
            lsm = my_channel_ocn['data/fields/So_omask/values'].reshape((ny_atm,nx_atm))
            #lon = my_channel_ocn['data/coords/values/face_lon'].reshape((ny_atm,nx_atm))
            #lat = my_channel_ocn['data/coords/values/face_lat'].reshape((ny_atm,nx_atm))

            # Constants
            missing_value = 1.0e20
            eps = 1.0e-12

            # Fix land sea mask
            lsm = np.where((lsm > missing_value/2.0e0), 0.0, lsm)
            lsm = np.clip(lsm, 0.0, 1.0) # removes tiny <0 or >1 artifacts
            lsm = np.where((lsm > eps) & (lsm < 1.0 - eps), 0.0, lsm)
            lsm = np.where(lsm >= 1.0 - eps, 1.0, lsm) # force near-1 to 1 exactly
            lsm = np.where(lsm <= eps, 0.0, lsm) # force near-0 to 0 exactly

            # Mask data over land with missing value
            sst = np.where(lsm > 0.0, sst, np.nan)

            # Set constant over land
            sst_min = 269.12622
            sst = np.where(np.isnan(sst), sst_min, sst)
            print(f"SST shape: {np.shape(sst)}, min: {np.min(sst)}, max: {np.max(sst)}", flush=True)

            # Write data to file for debugging
            #ds_new = xr.Dataset(
            #    data_vars = {
            #        'sst': (['latitude', 'longitude'], sst),
            #        'lsm': (['latitude', 'longitude'], lsm),
            #    },
            #    coords={
            #        "longitude": (['latitude', 'longitude'], lon),
            #        "latitude": (['latitude', 'longitude'], lat)
            #    }
            #)
            #ds_new.to_netcdf(f"import_{end_date}.nc", engine="netcdf4")

            # Create data structure to pass to the dataset
            import_vars = {
                "sst": {
                    "data": sst,
                    "scale_factor": 1.0,
                    "add_offset": 0.0,
                }
            }
            # Pass import variables to the dataset for two-way coupling
            dataset = AuroraDataset(data_path, output_path, start_date, end_date, time_delta, variables, import_vars=import_vars)
        else:
            print("*** One-way coupling enabled ***", flush=True)

            # No SST provided
            dataset = AuroraDataset(data_path, output_path, start_date, end_date, time_delta, variables)

        # Create DataLoader
        data_loader = DataLoader(
            dataset,
            batch_size=int(prediction_settings["batch_size"]), # Number of samples per batch - Use 1 for coupling since GeoGate provides one time step at a time
            num_workers=int(prediction_settings["num_workers"]), # Use multiple processes for faster data loading (adjust based on system)
            pin_memory=True, # Use pinned memory for faster GPU transfer (if using a GPU)
            persistent_workers=True if int(prediction_settings["num_workers"]) > 0 else False, # Keep workers alive for multiple epochs
            shuffle=False, # Shuffle data every epoch
            sampler=None, # No distributed sampler
            collate_fn=batch_collate_fn,
        )

        # Set the normalisation statistics for the new variables
        if "new_surf_vars" in generic_settings.keys():
            for key, val in generic_settings["new_surf_vars"].items():
                print(f"Setting normalisation statistics for {key} ({val['name']}): mean={val['mean']}, std={val['std']}", flush=True)
                locations[key] = float(val["mean"])
                scales[key] = float(val["std"])

        # Loop over the data loader and make predictions
        #for batch, (input, target) in enumerate(data_loader):
        for batch, input in enumerate(data_loader):
            with torch.inference_mode():
                # Get start time
                start_time = time.time()

                # Use an arbitary parameter of the model to derive the data type and device
                input = model.batch_transform_hook(input)
                p = next(model.parameters())
                input = input.type(p.dtype)
                input = input.crop(model.patch_size)

                # Make prediction
                pred = model.forward(input.to(device)).to("cpu")

                # Debug information
                for k, v in input.surf_vars.items():
                    print(f"{k} t-6h min/max = ", np.min(_np(input.surf_vars[k][:, 0,])), np.max(_np(input.surf_vars[k][:, 0,])))
                    print(f"{k} t+0h min/max = ", np.min(_np(input.surf_vars[k][:, 1,])), np.max(_np(input.surf_vars[k][:, 1,])))
                    print(f"{k} t+6h min/max = ", np.min(_np(pred.surf_vars[k][:, 0,])), np.max(_np(pred.surf_vars[k][:, 0,])))
                for k, v in input.atmos_vars.items():
                    print(f"{k} t-6h min/max = ", np.min(_np(input.atmos_vars[k][:, 0,])), np.max(_np(input.atmos_vars[k][:, 0,])))
                    print(f"{k} t+0h min/max = ", np.min(_np(input.atmos_vars[k][:, 1,])), np.max(_np(input.atmos_vars[k][:, 1,])))
                    print(f"{k} t+6h min/max = ", np.min(_np(pred.atmos_vars[k][:, 0,])), np.max(_np(pred.atmos_vars[k][:, 0,])))

                # Create dataset from predictions
                ds = batch_to_dataset(pred)

                # Add south pole to Aurora prediction
                new_lat = np.append(ds.latitude.values, -90.0)
                ds = ds.reindex({'latitude': new_lat}, method='nearest')

                # Save predictions to netCDF files
                ds.to_netcdf(ofile, engine="netcdf4")

                # Get end time
                end_time = time.time()

                # Measure estimated time for the batch
                batch_time = end_time - start_time

                # Print info
                print(f"Made {int(prediction_settings['steps'])*time_delta}h prediction for batch {batch+1}/{len(data_loader)} with time {forecast_time_str} in {batch_time:.4f} seconds.", flush=True)

    # List of variables used for coupling
    keep_vars = ['10u', '10v', 'msl', '2t', '2q', 'tp', 'lwdn', 'swdn']

    # Find previous prediction or ERA5 data
    previous_time_str = time_lb.strftime("%Y-%m-%dT%H:%M:%S")
    file_name = os.path.join(output_path, f"pred_{previous_time_str}.nc")
    if os.path.exists(file_name):
        print(f"Found previous prediction {file_name}", flush=True)
        ds_prev = xr.open_dataset(file_name, engine="netcdf4")
        ds_prev = ds_prev[keep_vars + ['time']]
    else:
        print(f"No previous prediction found for {previous_time_str}! Exiting ...", flush=True)
        sys.exit(1)

    # Perform temporal interpolation to model time, two rollout step is needed to perform: t+0h -> ? -> t+6h
    if perform_temporal_interpolation:
        if model_time > time_lb and model_time < time_ub:
            print(f"Interpolating data using {temporal_interpolation_method} method to model time: {model_time}", flush=True)

            # Keep only coupling variables
            ds = ds[keep_vars + ['time']]

            # Merge currrent prediction with previous prediction or ERA5 to perform temporal interpolation if needed
            ds = xr.concat([ds_prev, ds], dim="time", data_vars='all', coords='different', compat='equals')

            # Perform temporal interpolation
            ds_interp = ds.interp(time=model_time, method=temporal_interpolation_method)

            # Print statistics for debugging
            for var in ds_interp.data_vars:
                print(f"Statistics at {forecast_time_str} for {var}: min={ds_interp[var].min().values}, max={ds_interp[var].max().values}", flush=True)

            # Save interpolated data for debugging
            if debug:
                # Save interpolated file for debugging
                ds_interp.to_netcdf(os.path.join(output_path, f"pred_{model_time_str}_interp.nc"), engine="netcdf4")
        else:
            print("No temporal interpolation needed since forecast time matches the model time.", flush=True)
            # Since Aurora output is in float32, we need to convert to float64 to be compatible with GeoGate
            # TODO: Fix this in GeoGate to allow float32
            ds_interp = ds[keep_vars + ['time']].sel(time=model_time).astype(np.float64)
    else:
        print("No temporal interpolation requested. Use previous prediction for next 6-hours.", flush=True)
        # Since Aurora output is in float32, we need to convert to float64 to be compatible with GeoGate
        # TODO: Fix this in GeoGate to allow float32
        ds_interp = ds_prev.astype(np.float64)

    # Do not allow negative values for humidity, precipitation and shortwave radiation
    ds_interp['2q'] = ds_interp['2q'].clip(min=0.0)
    ds_interp['tp'] = ds_interp['tp'].clip(min=0.0)
    ds_interp['swdn'] = ds_interp['swdn'].clip(min=0.0)

    # Split total precipitation as snow and rain based on air temperature and add to dataset
    # TODO: Add snow to the Aurora model output and remove this post-processing step
    ds_interp['snow'] = ds_interp['tp'].where(ds_interp['2t'] <= 273.15, other=0.0, drop=False)
    ds_interp['rain'] = ds_interp['tp'].where(ds_interp['2t'] > 273.15, other=0.0, drop=False)

    # Return Conduit node with data
    my_node_return = Node()
    my_node_return.update(my_channel_atm)
    my_node_return['data/fields/Sa_z/values'] = ds_interp['10u'].values.reshape(-1)*0.0+10.0 # m, constant
    my_node_return['data/fields/Sa_u10m/values'] = ds_interp['10u'].values.reshape(-1) # m/s
    my_node_return['data/fields/Sa_u/values'] = ds_interp['10u'].values.reshape(-1) # m/s
    my_node_return['data/fields/Sa_pslv/values'] = ds_interp['msl'].values.reshape(-1) # Pa
    my_node_return['data/fields/Sa_pbot/values'] = ds_interp['msl'].values.reshape(-1) # Pa
    my_node_return['data/fields/Sa_t2m/values'] = ds_interp['2t'].values.reshape(-1) # K
    my_node_return['data/fields/Sa_tbot/values'] = ds_interp['2t'].values.reshape(-1) # K
    my_node_return['data/fields/Sa_v10m/values'] = ds_interp['10v'].values.reshape(-1) # m/s
    my_node_return['data/fields/Sa_v/values'] = ds_interp['10v'].values.reshape(-1) # m/s
    my_node_return['data/fields/Faxa_rain/values']  = ds_interp['rain'].values.reshape(-1)*1000.0 # m/s to kg/m^2/s 
    my_node_return['data/fields/Faxa_snow/values']  = ds_interp['snow'].values.reshape(-1)*1000.0 # m/s to kg/m^2/s 
    my_node_return['data/fields/Sa_q2m/values'] = ds_interp['2q'].values.reshape(-1) # kg/kg
    my_node_return['data/fields/Sa_shum/values'] = ds_interp['2q'].values.reshape(-1) # kg/kg
    my_node_return['data/fields/Faxa_lwdn/values']  = ds_interp['lwdn'].values.reshape(-1) # W/m2
    my_node_return['data/fields/Faxa_swdn/values'] = ds_interp['swdn'].values.reshape(-1) # W/m2
    my_node_return['data/fields/Faxa_swvdr/values'] = ds_interp['swdn'].values.reshape(-1)*0.28 # W/m2
    my_node_return['data/fields/Faxa_swndr/values'] = ds_interp['swdn'].values.reshape(-1)*0.31 # W/m2
    my_node_return['data/fields/Faxa_swvdf/values'] = ds_interp['swdn'].values.reshape(-1)*0.24 # W/m2
    my_node_return['data/fields/Faxa_swndf/values'] = ds_interp['swdn'].values.reshape(-1)*0.17 # W/m2
    if debug:
        my_node_return.save(f"pred_{model_time_str}")
