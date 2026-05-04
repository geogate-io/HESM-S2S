# HESM-S2S: Hybrid Earth System Model for S2S Prediction

[![DOI](https://zenodo.org/badge/1101444353.svg)](https://doi.org/10.5281/zenodo.20019280)

The HESM-S2S modeling system is a hybrid modeling application that combines a AI/ML weather model with MOM6, CICE6, CMEPS and CDEPS to create S2S application.

## Configuration

The initial configuration is based on UFS WM `datm_cdeps_mx025_cfsr` regression test (RT).

<img width="694" height="903" alt="Fig01" src="https://github.com/user-attachments/assets/b753112b-4304-4df8-9f2b-c693ae5ca026" />

## Usage

### Cloning Repository

The HESM-S2S modeling system includes four sub-components: (1) GeoGate (as data producer), (2) the Modular Ocean Model (MOM6) ocean model component, (3) the CICE6 sea-ice model, and (4) the Community Mediator for Earth Prediction Systems (CMEPS). To clone the repository, the following command can be used:

```console
$ git clone --recursive https://github.com/geogate-io/HESM-S2S
```

## The Aurora Prediction Scripts

### One-way Coupled Simulations

1. The scripts data_aurora.py and data_aurora_utils.py in the run folder primarily force the model using the ERA5 dataset each time they are triggered. This approach is considered a partly free prediction because it reinitializes the model for every prediction to forecast t+6h and t+12h (two autoregressive rollouts) while driving the underlying physics-based model.

2. The scripts data_aurora_v2.py and data_aurora_utils_v2.py in the run folder primarily force the model with its output each time, except at the beginning of the coupled simulation when there are insufficient predictions to trigger the next time step. It begins with the ERA5 dataset and subsequently uses the previous Aurora predictions for all variables in autoregressive fashion. This step is categorized as a free mode prediction, forecasting t+6h, using previous forecasts to perform temporal interpolation and enforcing an underlying physics-based model.

3. The scripts data_aurora_v3.py and data_aurora_utils_v3.py are similar to those used in (2), with the exception that they replace the SST from the ERA5 dataset instead of utilizing the previous Aurora prediction. The experiment is intended to evaluate the model's sensitivity regarding the accuracy of SST data used.

### Two-way Coupled Simulations

1. The scripts data_aurora_v2.py and data_aurora_utils_v2.py are very similar to those used in (one-way coupled case, 2); however, they replace the SST with data from the active ocean component (MOM6) instead of using the previous Aurora prediction. This aims to assess the model's sensitivity in terms of accuracy and stability concerning the SST data employed.
