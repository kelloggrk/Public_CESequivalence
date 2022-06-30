/*
This file loads the raw EIA 923 data and converts it to .dta
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
log using "$logdir/Load_EIA923_log.txt", replace text


// Load EIA 923 data
clear all
import excel "$rawdir/EIA923_Schedules_2_3_4_5_M_12_2019_Final_Revision.xlsx", /*
	*/ sheet("Page 1 Generation and Fuel Data") cellrange(A7)
rename A PlantID
rename D PlantName
rename G PlantState
rename I NERCregion
rename K NAICS
rename L EIAsectornum
rename M EIAsectorname
rename N PrimeMover
rename O FuelType
rename P AERFuelType
rename S QuantityUnits
rename CN TotalFuelQuantity
rename CO ElecFuelQuantity
rename CP TotalFuelmmBtu
rename CQ ElecFuelmmBtu
rename CR NetGenMWh
drop B-C E-F H J Q-R T-CM CS

// Save intermediate data file
sort PlantID FuelType PrimeMover
saveold "$outdir/EIA923.dta", version(14) replace


// Close out the log file
log close
