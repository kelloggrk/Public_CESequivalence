/*
This file does three things:
Assigns emission factors to each unit
Assigns O&M cost factors to each unit
Saves .csv files for export to Matlab model
*/


clear all
set more off
capture log close

* Set local git directory and local dropbox directory
*
* Calling the path file works only if the working directory is nested in the repo
* This will be the case when the file is called via any scripts in the repo.
* Otherwise you must cd to at least the home of the repository in Stata before running.
pathutil split "`c(pwd)'"
while "`s(filename)'" != "CESequivalence" && "`s(filename)'" != "cesequivalence" {
  cd ..
  pathutil split "`c(pwd)'"
}

do "globals.do"


// Input and output directories
global rawdir = "$dropbox/RawData/EIAdata"
global outdir = "$dropbox/IntermediateData/EIAdata"
global codedir = "$repodir/code/build/EIAdata"
global logdir = "$codedir/LogFiles"


// Create a plain text log file to record output
// Log file has same name as do-file, with _log.txt appended
log using "$logdir/ExportEIADataToMatlab_log.txt", replace text

// Double precision for egen commands
set type double




********************************************************************************
* Load data and compute emissions rate
use "$outdir/Merged_923_and_3_1_Generator.dta", clear

* Emissions rate in metric tons CO2 per MWh
gen EmissionsRate = Emissions / NetGenMWh




********************************************************************************
* Input O&M cost factors
* Use the "Assumptions to the AEO" 2021, given in table 3
gen VarOM = 0		// variable O&M, in $/MWh
tab FuelType Tech
tab FuelType PrimeMover
replace VarOM = 4.52 if Tech=="Coal"
replace VarOM = (2.56+1.88)/2 if PrimeMover=="CC" & Tech~="Coal"	// average single and multi shaft
replace VarOM = 5.72 if PrimeMover=="IC" & Tech~="Coal"
replace VarOM = (4.72+4.52)/2 if PrimeMover=="GT" & Tech~="Coal"	// avg aeroderivative and industrial frame
replace VarOM = (2.56+1.88)/2 if PrimeMover=="ST" & Tech~="Coal"	// treat ST like CC

gen FixedOM = 0		// fixed O&M, in $/kW
replace FixedOM = 40.79 if Tech=="Coal"
replace FixedOM = (14.17+12.26)/2 if PrimeMover=="CC" & Tech~="Coal"	// average single and multi shaft
replace FixedOM = 35.34 if PrimeMover=="IC" & Tech~="Coal"
replace FixedOM = (16.38+7.04)/2 if PrimeMover=="GT" & Tech~="Coal"		// avg aeroderivative and industrial frame
replace FixedOM = (14.17+12.26)/2 if PrimeMover=="ST" & Tech~="Coal"	// treat ST like CC



********************************************************************************
* Ongoing capex in $/kW. Discussed on pp.16-17 of "Assumptions to the AEO" 2021
gen Capex = 0
replace Capex = 11 if inlist(PrimeMover,"CC","ST") & Tech~="Coal"	// oil and gas steam units

* Coal unit capex is a function of age and whether there is a scrubber (FGD)
* Handle age correction within Matlab rather than here
* Here, need to pull in scrubber info from egrid2019_data.xlsx
sort PlantID PrimeMover FuelType
tempfile temp_unitdata
save "`temp_unitdata'"
clear
import excel "$rawdir/egrid2019_data.xlsx", /*
	*/ sheet("UNT19") cellrange(A3)
rename E PlantID
rename G PrimeMover
rename M FuelType
rename AC FGD
keep PlantID PrimeMover FuelType FGD
* Create 0/1 scrubber flag
replace FGD = "0" if FGD==""
replace FGD = "1" if FGD~="0"
destring FGD, replace
* Just keep coal units
keep if inlist(FuelType,"BIT","LIG","PC","RC","SGC","SUB","WC")
duplicates drop
duplicates report PlantID PrimeMover FuelType	// a small number of observations have units with and w/o scrubbers
* Set up so that if any unit in a PlantID x PM * FT has a scrubber, they all do
bysort PlantID PrimeMover FuelType: egen FGDm = max(FGD)
replace FGD = FGDm
drop FGDm
duplicates drop
sort PlantID PrimeMover FuelType
tempfile temp_FGDdata
save "`temp_FGDdata'"
* Now merge the FGD info into the main file
use "`temp_unitdata'", clear
merge 1:1 PlantID PrimeMover FuelType using "`temp_FGDdata'" // 239 of 260 coal plants merge
drop if _merge==2
drop _merge
replace FGD = 0 if FGD==.
* Capex intercept for coal plants
replace Capex = 16.53 + 5.68 * FGD if Tech=="Coal"
drop FGD

* Save complete data
sort UnitID
saveold "$outdir/MergedDataWithEmissionsAndCosts.dta", version(14) replace




********************************************************************************
* Export two output files to csv
* First is text data, second is numerical
keep UnitID-Tech
tostring UnitID, replace
tostring PlantID, replace
export delimited using "$outdir/UnitStringData.csv", replace
use "$outdir/MergedDataWithEmissionsAndCosts.dta", clear
keep UnitID ElecFuelmmBtu NetGenMWh Emissions CapacityMW StartYear EmissionsRate VarOM FixedOM Capex
export delimited using "$outdir/UnitNumericData.csv", replace



// Close out the log file
log close
