# CESequivalence
## Repository for "Carbon Pricing, Clean Electricity Standards, and Clean Electricity Subsidies on the Path to Zero Emissions"

### Versions
- The current version of this repo corresponds to the paper as submitted to *Environmental and Energy Policy and the Economy* on 30 June, 2022

### Organization
- All of the code for this project is stored in this repository. To run the code, you need to clone this repo to your local machine (or copy the files directly, preseving the subfolder structure).
  * The local folder holding the code files is referred to as `repodir` below.
- All raw data files are available [here](https://www.dropbox.com/sh/dvfpdb9u85qaqqu/AABlWR12dg309S8NqwIlOfrEa?dl=0) in the `RawData` folder.
  * This link also includes an intermediate data (`IntermediateData`) folder that is populated with the output from the Stata scripts. It also includes an `CartoonFigures` folder that contains the paper's figure 1.
  * Users should download the `RawData`, `IntermediateData`, and `CartoonFigures` folders together into a single folder. This folder is referred to as `dropbox` below.


### Stata
- Code has been verifed to run on Windows OS 64-bit Stata SE v17. The script `code/stata_installs.do` handles the one package that must be installed (`pathutil`). The batch script includes this installation.
- To run the Stata code, you need a file called `globals.do` stored in your local root CESequivalence repo folder. (`globals.do` is .gitignored)
    - `globals.do` should look like the below, pointing to your own directories:
```
global repodir = "C:/Work/CESequivalence"
global dropbox = "C:/Users/kelloggr/Dropbox/CESequivalence"
```

### Matlab
- Code has been verified to run on Windows OS Matlab R2021b. No extra package installations are required.
- To run the Matlab code, you need a file called `globals.m` stored in your local root CESequivalence repo folder. (`globals.m` is .gitignored)
    - `globals.m` should look like the below, pointing to your own directories:
```
repodir = 'C:/Work/CESequivalence';
dropbox = 'C:/Users/kelloggr/Dropbox/CESequivalence';
```
- `code/analysis/mainscript.m` is the front-end script that sets up the model parameters, instantiates the model objects, calls the methods that generate the results, and generates the figures and other quantitative results. 
- The model objects are defined in `GenModel.m` and `GenModel_GasCoal.m`. GenModel.m is the superclass and does not model coal-to-gas substitution in response to carbon pricing. `GenModel_GasCoal.m` is a subclass that models this substitution.
- If you are unfamiliar with object-oriented programming in Matlab, see resources available [here](https://www.mathworks.com/discovery/object-oriented-programming.html)


### LaTex
- A full LaTex build is required to compile the paper. The compiled paper will be located in the repo as `/paper/EEPEpaper.pdf`.

### Batch script
- The file `CES_bash_file.sh` will run all Stata, Matlab, and LaTex code in order, resulting in the final compiled paper. It must be called from a bash shell.
  * The root directory definitions in this script for the locally cloned repository and the dropbox data need to point to your own directories.
  * See the README header in `CES_bash_file.sh` for guidelines on running the script.
  * Note that the script begins by deleting the files in the `IntermediateData` folder and all results figures and quantitative output from the repo.

