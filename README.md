# HESM-S2S: Hybrid Earth System Model for S2S Prediction

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
