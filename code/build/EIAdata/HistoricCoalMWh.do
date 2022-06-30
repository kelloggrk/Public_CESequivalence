/*
This file loads annual net generation from coal for 2006--2012 and computes 
the average generation for that timer period
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
global rawdir = "$dropbox/RawData/EIAdata/AggregatedHistoricalGen"
global outdir = "$dropbox/IntermediateData/EIAdata/AggregatedHistoricalGen"
global codedir = "$repodir/code/build/EIAdata"
global logdir = "$codedir/LogFiles"


// Create a plain text log file to record output
// Log file has same name as do-file, with _log.txt appended
log using "$logdir/HistoricCoalMWh_log.txt", replace text


// Data come in three Excel files, one for each of utilities, IPP, and industrial cogen
// Load these data one at a time, average over years, then sum across files
// Units in raw data are thousands of MWh (i.e. GWh). Will multiply by 1000 to
// export output in MWh

// Load data for utilities
clear all
import excel "$rawdir/table_1_02.xlsx", cellrange(B6:B12)
sum B
local MWhUtil = `r(mean)'
di(`MWhUtil')

// Load data for IPPs
clear all
import excel "$rawdir/table_1_03.xlsx", cellrange(B6:B12)
sum B
local MWhIPP = `r(mean)'
di(`MWhIPP')

// Load data for industrial cogen
clear all
import excel "$rawdir/table_1_05.xlsx", cellrange(B6:B12)
sum B
local MWhInd = `r(mean)'
di(`MWhInd')

// Sum, change units to MWh, and save
local MWhCoal = (`MWhUtil' + `MWhIPP' + `MWhInd') * 1000
di(`MWhCoal')
file open MWhCoal_2006_2012 using "$outdir/MWhCoal_2006-2012.csv", write replace
file write MWhCoal_2006_2012 "`MWhCoal'"
file close MWhCoal_2006_2012

// Close out the log file
log close
