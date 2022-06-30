/*
This file loads the raw EIA 3_1_Generator data and converts it to .dta
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
log using "$logdir/Load_3_1_Generator_log.txt", replace text


// Load EIA 923 data
clear all
import excel "$rawdir/3_1_Generator_Y2019.xlsx", /*
	*/ sheet("Operable") cellrange(A3)
	
	
rename C PlantID
rename D PlantName
rename E PlantState
rename G UnitID
rename H Tech
rename I PrimeMover
rename P CapacityMW
rename Z StartMonth
rename AA StartYear
rename AH FuelType
rename AI FuelType2
drop A-B F J-O Q-Y AB-AG AJ-BU


// Save intermediate data file
sort PlantID FuelType PrimeMover UnitID
saveold "$outdir/3_1_Generator.dta", version(14) replace


// Close out the log file
log close
