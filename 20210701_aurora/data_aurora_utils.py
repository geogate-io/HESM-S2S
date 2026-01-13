import os
import torch
import pandas as pd
import numpy as np
import xarray as xr
from aurora import Batch, Metadata
from torch.utils.data import Dataset
from typing import Dict, List, Tuple
from datetime import datetime, timedelta

class AuroraDataset(Dataset):
    """
    Aurora Dataset class for loading ERA5 data for training, validation and testing.
    Provides paired batches: input (t-6h, t) and target (t+6h).
    """
    def __init__(self, data_path: str, start_date: str, end_date: str, time_delta: int, variables: Dict[str, Dict[str, str]], import_vars: Dict[str, Dict[str, float]] = None) -> None:
        self.data_path = data_path
        self.variables = variables
        self.import_vars = import_vars
        self.start_indx = 1 # Because we need t-6h for input
        self.start_date = datetime.strptime(start_date, "%Y-%m-%dT%H:%M:%S")
        self.end_date = datetime.strptime(end_date, "%Y-%m-%dT%H:%M:%S")
        self.time_delta = timedelta(hours=time_delta)
        self.time_array = pd.date_range(self.start_date, self.end_date, freq=self.time_delta).strftime('%Y-%m-%dT%H:%M:%S').to_list()
        self.len = len(self.time_array) - 2

    def __len__(self) -> int:
        return self.len

    def __blend__(self, da: xr.DataArray, var: np.ndarray, name: str, scale: float = 1.0, add_offset: float = 0.0, missing_value=1.0e20) -> xr.DataArray:
        """
        Blend provided data with existing variable in the dataset
        """
        # Create a new DataArray from numpy array
        da_new = xr.DataArray(
            var,
            dims=('latitude', 'longitude'),
            coords=da.isel(latitude=slice(None, -1)).coords.drop_vars(['time']),
            name=name
        )

        # We need to pad the new data with a row of NaNs at the end to match the shape of the ERA5 variable (721, 1440) vs. (720, 1440)
        da_new_padded = xr.concat([da_new, xr.full_like(da_new.isel(latitude=-1), np.nan)], dim="latitude").fillna(missing_value)
        da_new_padded = da_new_padded.assign_coords(latitude=("latitude", da.latitude.values))

        # Extend the new data to match the time dimension of the ERA5 variable (2 time steps)
        da_new_padded_ext = xr.concat([da_new_padded.expand_dims({"time": [i]}) for i in range(2)], dim="time")
        da_new_padded_ext = da_new_padded_ext.chunk({'time': 1, 'latitude': -1, 'longitude': -1})
        da_new_padded_ext = da_new_padded_ext.assign_coords(time=("time", da.time.values))

        # Apply scale and offset
        da_new_padded_ext = da_new_padded_ext * scale + add_offset

        # Blend the new data with the existing variable
        da_blended = da.where(da_new_padded_ext > missing_value/2.0, da_new_padded_ext)

        return da_blended

    def __getbatch__(self, idxs: List[int], remove_south_pole=False, has_import=False) -> Batch:
        # Define required dictionaries
        surf_vars = {}
        static_vars = {}
        atmos_vars = {}

        # Load datasets
        file_list = []
        for idx in idxs:
            time_str = self.time_array[idx]
            file_name = f"data_{time_str}.nc"
            file_list.append(os.path.join(self.data_path, file_name))
        ds = xr.open_mfdataset(file_list, data_vars="all", chunks='auto', engine="netcdf4")

        # Fix for target tensors since Aurora model does not return data for the south pole
        if remove_south_pole:
            ds = ds.isel(latitude=slice(None, -1))

        # Batch
        for section in self.variables.keys():
            if section == "surf":
                for key, val in self.variables[section].items():
                    # Accumulated variables, convert from per hour to per second
                    if key in ["swnet", "lwnet", "swdn", "lwdn", "tp"]:
                        surf_vars[key] = torch.from_numpy((ds[val]/3600.0).values[None])
                    else:
                        surf_vars[key] = torch.from_numpy(ds[val].values[None])
                    # Two-way coupling: check if we need to import variables and update input data
                    if self.import_vars is not None and has_import:
                        if key in self.import_vars.keys():
                            # Get imported variable
                            data = self.import_vars[key]["data"]
                            add_offset = self.import_vars[key]["add_offset"]
                            scale_factor = self.import_vars[key]["scale_factor"]
                            missing_value = self.import_vars[key]["missing_value"]
                            # Update input data with provided variable
                            da_blended = self.__blend__(ds[val], data, name=key, scale=scale_factor, add_offset=add_offset, missing_value=missing_value)
                            surf_vars[key] = torch.from_numpy(da_blended.values[None])
            elif section == "static":
                for key, val in self.variables[section].items():
                    if len(idxs) > 1:
                        static_vars[key] = torch.from_numpy(ds[val].isel(time=0).values)
                    else:
                        static_vars[key] = torch.from_numpy(ds[val].values)
            elif section == "atmos":
                for key, val in self.variables[section].items():
                    atmos_vars[key] = torch.from_numpy(ds[val].values[None])

        _batch = Batch(
            surf_vars=surf_vars,
            static_vars=static_vars,
            atmos_vars=atmos_vars,
            metadata=Metadata(
                lat=torch.from_numpy(ds.latitude.values),
                lon=torch.from_numpy(ds.longitude.values),
                time=(ds.time.values.astype("datetime64[s]").tolist()[-1],),
                atmos_levels=tuple(int(level) for level in ds.level.values)
            ),
        )

        return _batch

    def __getitem__(self, idx: int) -> Tuple[Batch, Batch]:
        # Update index since we need t-6h for input
        idx = idx + self.start_indx

        # Get input batch
        input_idx = [idx-1, idx]
        input_batch = self.__getbatch__(input_idx, has_import=True)

        # Get target batch
        target_idx = [idx+1]
        target_batch = self.__getbatch__(target_idx, remove_south_pole=True)
        
        return input_batch, target_batch

def aurora_collate_fn(batches: List[Tuple[Batch, Batch]]) -> Tuple[Batch, Batch]:
    """
    Custom collate function to combine a list of Aurora Batch objects into a single batch.
    """
    inputs, targets = zip(*batches)
    return(batch_collate_fn(inputs), batch_collate_fn(targets))

def batch_collate_fn(batches: List[Batch]) -> Batch:
    """
    This function takes a list of Aurora Batch objects and combines them into a single batch of tensors
    """
    # Initialize result Batch
    result = Batch(
        atmos_vars=batches[0].atmos_vars,
        surf_vars=batches[0].surf_vars,
        static_vars=batches[0].static_vars,
        metadata=batches[0].metadata
    )
    # Merge tensors for surfface variables
    for key in result.surf_vars.keys():
        for idx in range(1, len(batches)):
            result.surf_vars[key] = torch.cat([result.surf_vars[key], batches[idx].surf_vars[key]], dim=0)
    
    # Merge tensors for atmospheric variables
    for key in result.atmos_vars.keys():
        for idx in range(1, len(batches)):
            result.atmos_vars[key] = torch.cat([result.atmos_vars[key], batches[idx].atmos_vars[key]], dim=0)    
    
    # Merge tensors for static variables
    result.static_vars = batches[0].static_vars

    # Add metadata, this is not working since Aurora fails with metadata as list
    #result.metadata = [t for item in batches for t in item.metadata.time]

    return result

def _np(x: torch.Tensor) -> np.ndarray:
    return x.detach().cpu().numpy()

def batch_to_dataset(batch) -> xr.Dataset:
    ds = xr.Dataset(
        data_vars = {
            **{key: (("latitude", "longitude"), _np(value)) for key, value in batch.static_vars.items()},
            **{key: (("batch", "time", "latitude", "longitude"), _np(value)) for key, value in batch.surf_vars.items()},
            **{key: (("batch", "time", "level", "latitude", "longitude"), _np(value)) for key, value in batch.atmos_vars.items()},
        },
        coords={
            "rollout_step": batch.metadata.rollout_step,
            "time": list(batch.metadata.time),
            "level": list(batch.metadata.atmos_levels),
            "latitude": _np(batch.metadata.lat),
            "longitude": _np(batch.metadata.lon),
        },
    )
    return ds
