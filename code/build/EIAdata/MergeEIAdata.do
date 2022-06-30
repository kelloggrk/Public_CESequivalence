/*
Examine and merge the EIA 923 and 3_1_Generator data
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
global texdir = "$repodir/paper/single_num_tex"


// Create a plain text log file to record output
// Log file has same name as do-file, with _log.txt appended
log using "$logdir/MergeEIAdata_log.txt", replace text

// Double precision for egen commands
set type double




********************************************************************************
* Start with 3_1_Generator data
use "$outdir/3_1_Generator.dta", clear
* Keep only lower 48
drop if inlist(PlantState,"AK","HI")
* Keep fossil fuel technology types
tab FuelType
tab Tech
keep if strrpos(Tech,"Coal")~=0 | strrpos(Tech,"Natural Gas")~=0 | /*
	*/ strrpos(Tech,"Petroleum")~=0 | strrpos(Tech,"Other Gases")~=0
tab Tech
* Get rid of compressed air
drop if PrimeMover=="CE"
* Get rid of "Other Natural Gas", which is all fuel cell
drop if Tech=="Other Natural Gas"
* Keep only fossil fuel types
keep if inlist(FuelType,"BIT","DFO","JF","KER","LIG","NG","OG") /*
	*/ | inlist(FuelType,"PC","PG","RC","RFO","SGC","SGP","SUB","WC","WO")

* Change start date to year and decimal month
gen Start = StartYear + StartMonth / 12
drop StartMonth StartYear
rename Start StartYear
	
* Collapse to plant, prime mover, and fuel type
* Dropping fuel type 2 since secondary fuel types will merge in with EIA 923
sort PlantID PrimeMover FuelType
duplicates report PlantID PrimeMover FuelType
collapse(sum) CapacityMW (mean) StartYear, by(PlantID PrimeMover FuelType)
duplicates report PlantID PrimeMover FuelType		// no dupes

* Within each tech and fuel type, combine the prime movers associated with CCGTs (CA, CS, and CT)
replace PrimeMover = "CC" if inlist(PrimeMover,"CA","CS","CT")
sort PlantID PrimeMover FuelType
collapse(sum) CapacityMW (mean) StartYear, by(PlantID PrimeMover FuelType)

* Create "unit" ID, which will be the final unit of observation
duplicates report PlantID PrimeMover FuelType		// no dupes
sort PlantID PrimeMover FuelType
gen UnitID = _n

* Save ready to merge
count
sort PlantID PrimeMover FuelType
tempfile temp_3_1_Generator
save "`temp_3_1_Generator'"
tab PrimeMover
tab FuelType

* Collapse to a dataset that is PlantID x PrimeMover
sort PlantID PrimeMover
collapse (sum) CapacityMW (mean) StartYear (max) UnitID, by(PlantID PrimeMover)
sort PlantID PrimeMover
tempfile temp_3_1_plantprimemoverdata
save "`temp_3_1_plantprimemoverdata'"

* Create a list of plant IDs by prime movers
keep PlantID PrimeMover
duplicates drop
sort PlantID PrimeMover
tempfile temp_3_1_plantprimemoverlist
save "`temp_3_1_plantprimemoverlist'"

* Create list of plant IDs
keep PlantID
duplicates drop
sort PlantID
tempfile temp_3_1_plantlist
save "`temp_3_1_plantlist'"




********************************************************************************
* Now work with the EIA 923 data
use "$outdir/EIA923.dta", clear

* Keep only lower 48
drop if inlist(PlantState,"AK","HI")

* Drop cogen
drop if inlist(EIAsectornum,3,5,7)
drop NAICS-EIAsectorname
// Rapids Energy Center in MN is actually cogen, see https://www.mnpower.com/Community/Tours
// data for this plant show non-credibly low heat rate
drop if PlantID==10686	

* Keep only fossil fuel generators (and drop FuelType==SC which has no generation)
drop AERFuelType	// AERFuelType doesn't match 3_1_Generator, but FuelType does
keep if inlist(FuelType,"BIT","DFO","JF","KER","LIG","NG","OG") /*
	*/ | inlist(FuelType,"PC","PG","RC","RFO","SGC","SGP","SUB","WC","WO")
* Drop fuel cells, compressed air, and other prime movers ("other" is a small number of refineries)
drop if inlist(PrimeMover,"FC","CE","OT")
* Drop state fuel level increment
drop if PlantID==99999
* Save temp dataset for use later
tempfile temp_raw923
save "`temp_raw923'"

* Drop fuel quantity info, which can't be summed within dual fuel plants
drop QuantityUnits TotalFuelQuantity ElecFuelQuantity

* Drop entries with <=0 generation
drop if NetGenMWh<=0

* Collapse to plant, prime mover, fuel type
sort PlantID PrimeMover FuelType
duplicates report PlantID PrimeMover FuelType		// very few dupes
collapse(sum) TotalFuelmmBtu ElecFuelmmBtu NetGenMWh, by(PlantID PrimeMover FuelType)

* For plant 7546, change unit with PrimeMover=="GT" to "CT". The GT data are clearly wrong
* as they imply an impossibly low heat rate. This change will result in the units being combined
replace PrimeMover = "CT" if PlantID==7546 & PrimeMover=="GT"

* Within each fuel type, combine the prime movers associated with CCGTs (CA, CS, and CT)
tab FuelType if inlist(PrimeMover,"CA","CS","CT")
replace PrimeMover = "CC" if inlist(PrimeMover,"CA","CS","CT")
sort PlantID PrimeMover FuelType
collapse(sum) TotalFuelmmBtu ElecFuelmmBtu NetGenMWh, by(PlantID PrimeMover FuelType)

* Compute emissions for each plant
* First define emissions factors, which come from EIA Electric Power Annual 2019
* https://www.eia.gov/electricity/annual/archive/pdf/epa_2019.pdf
gen EmissionsFactor = 0		// units input as kg CO2 per mmBtu
replace EmissionsFactor = 93.30 if FuelType=="BIT"
replace EmissionsFactor = 73.16 if FuelType=="DFO"
replace EmissionsFactor = 70.90 if FuelType=="JF"
replace EmissionsFactor = 72.30 if FuelType=="KER"
replace EmissionsFactor = 97.70 if FuelType=="LIG"
replace EmissionsFactor = 53.07 if FuelType=="NG"
replace EmissionsFactor = 63.07 if inlist(FuelType,"OG","PG") 	// treat other gas like propane
replace EmissionsFactor = 102.1 if FuelType=="PC"
replace EmissionsFactor = 93.30 if FuelType=="RC"
replace EmissionsFactor = 78.79 if FuelType=="RFO"
replace EmissionsFactor = 93.30 if FuelType=="SGC"	// treat coal syn gas like bituminous
replace EmissionsFactor = 97.20 if FuelType=="SUB"
replace EmissionsFactor = 93.30 if FuelType=="WC"
replace EmissionsFactor = 95.25 if FuelType=="WO"
tab EmissionsFactor
* Convert to metric tons CO2 per mmBtu
replace EmissionsFactor = EmissionsFactor / 1000
* Compute total emissions
gen Emissions = EmissionsFactor * ElecFuelmmBtu
drop EmissionsFactor

* Save ready to merge
count
sort PlantID PrimeMover FuelType
tempfile temp_923
save "`temp_923'"

egen TotMWh = sum(NetGenMWh)	// 2.313e+09. Check against total after final append
egen TotEmissions = sum(Emissions)	// 1.514e+09

* Create a list of plant IDs by prime movers
keep PlantID PrimeMover
duplicates drop
sort PlantID PrimeMover
tempfile temp_923_plantprimemoverlist
save "`temp_923_plantprimemoverlist'"

* Create list of plant IDs
keep PlantID
duplicates drop
sort PlantID
tempfile temp_923_plantlist
save "`temp_923_plantlist'"




********************************************************************************
* Merge with 3_1_Generator data
use "`temp_923'", clear
sort PlantID PrimeMover FuelType
tab PrimeMover
tab FuelType
tab FuelType if PrimeMover=="ST"
merge 1:m PlantID PrimeMover FuelType using "`temp_3_1_Generator'"
bysort _merge: sum NetGenMWh
* Output share of generation that successfully merged
sum NetGenMWh if _merge==3
local MergedMWh = `r(mean)' * `r(N)'
sum NetGenMWh if _merge==1
local UnmergedMWh = `r(mean)' * `r(N)'
local MergedPct = round(`MergedMWh' / (`MergedMWh' + `UnmergedMWh') * 100)
echo `MergedPct'
file open TEX using "$texdir/MergedMWhPct.tex", write replace
file write TEX "`MergedPct'\%"
file close TEX
drop if _merge==2
* There are two types of _merge==1. First are cases where the PlantID x PM merges but FuelType does not
* Second are cases where the PlantID x PM does not show up at all in 3_1_Generator
gen RawMergeFlag = 0
replace RawMergeFlag = 1 if _merge==3
drop _merge
sort PlantID PrimeMover FuelType
tempfile temp_rawmerge
save "`temp_rawmerge'"




********************************************************************************
* Create a list of 923 plants that flags match vs no match in 3_1_Generator
use "`temp_923_plantlist'", clear
merge 1:1 PlantID using "`temp_3_1_plantlist'"
drop if _merge==2
gen PlantMerge = 0
replace PlantMerge = 1 if _merge==3
drop _merge
sort PlantID
tempfile temp_plantmergeflags
save "`temp_plantmergeflags'"




********************************************************************************
* Create a list of 923 plants and prime movers flagging match vs no match in 3_1_Generator
* See how these flags line up with merge based on plant ID alone
use "`temp_923_plantprimemoverlist'", clear
merge 1:1 PlantID PrimeMover using "`temp_3_1_plantprimemoverlist'"
drop if _merge==2
gen PlantPMMerge = 0
replace PlantPMMerge = 1 if _merge==3
drop _merge
sort PlantID PrimeMover
tempfile temp_plantPMmergeflags
save "`temp_plantPMmergeflags'"
sort PlantID
merge m:1 PlantID using "`temp_plantmergeflags'"
drop _merge
tab PlantPMMerge PlantMerge	// 8 of 2134 PlantMerge==1 have PlantPMMerge==0. 115 PlantMerge==0
* So most of the time when PlantID x PM doesn't merge, it's because PlantID doesn't merge




********************************************************************************
* Deal with merges where some (but not all) fuel types within a matching PlantID x PM do not match
* Treat these as dual fuel units and collapse down to the PlantID x PM level
use "`temp_rawmerge'", clear

* Drop PlantID x PM that do not match at all
sort PlantID PrimeMover
merge m:1 PlantID PrimeMover using "`temp_plantPMmergeflags'"
drop _merge
keep if PlantPMMerge==1
drop PlantPMMerge

* Keep PlantID x PM groups where there are partial merges
bysort PlantID PrimeMover: egen IncFlag = sd(RawMergeFlag)
replace IncFlag = 0 if IncFlag==.
replace IncFlag = 1 if IncFlag>0
keep if IncFlag==1
drop IncFlag

* Within all PlantID x PM where some fuels didn't merge, sum capacity and copy over start year
* Sum inputs and outputs as well
replace CapacityMW = 0 if RawMergeFlag==0
replace UnitID = 0 if RawMergeFlag==0
bysort PlantID PrimeMover: egen SumFuel = sum(TotalFuelmmBtu)
bysort PlantID PrimeMover: egen SumElecFuel = sum(ElecFuelmmBtu)
bysort PlantID PrimeMover: egen SumMWh = sum(NetGenMWh)
bysort PlantID PrimeMover: egen SumEmit = sum(Emissions)
bysort PlantID PrimeMover: egen SumCap = sum(CapacityMW)
bysort PlantID PrimeMover: egen SumYear = mean(StartYear)
bysort PlantID PrimeMover: egen SumUnit = max(UnitID)

* Find the fuel type that is associated with the most MWh
bysort PlantID PrimeMover: egen MaxMWh = max(NetGenMWh)
gen NewFuel = ""
replace NewFuel = FuelType if NetGenMWh==MaxMWh
* Copy the predominant fuel type to the PlantID x PM group
gen NewFuel2 = ""
levelsof FuelType, local(fuellist)
foreach val of local fuellist {
	bysort PlantID PrimeMover: egen tag = max(inlist(NewFuel,"`val'"))
	replace NewFuel2 = "`val'" if tag==1
	drop tag
}
drop MaxMWh NewFuel

* Collapse to PlantID x PM dataset
drop FuelType-RawMergeFlag
rename SumFuel TotalFuelmmBtu
rename SumElecFuel ElecFuelmmBtu
rename SumMWh NetGenMWh
rename SumEmit Emissions
rename SumCap CapacityMW
rename SumYear StartYear
rename SumUnit UnitID
rename NewFuel2 FuelType
order PlantID PrimeMover FuelType
duplicates drop
duplicates report PlantID PrimeMover

* Sort and save
sort PlantID PrimeMover FuelType
tempfile temp_partialmergegroup
save "`temp_partialmergegroup'"




********************************************************************************
* Deal with PlantID x PMs that match across datasets but no fuel types match
use "`temp_rawmerge'", clear

* Drop PlantID x PM that do not match at all
sort PlantID PrimeMover
merge m:1 PlantID PrimeMover using "`temp_plantPMmergeflags'"
drop _merge
keep if PlantPMMerge==1
drop PlantPMMerge

* Keep PlantID x PM groups where no fuel merges
bysort PlantID PrimeMover: egen IncFlag = sd(RawMergeFlag)
replace IncFlag = 0 if IncFlag==.
replace IncFlag = 1 if IncFlag>0
keep if IncFlag==0 & RawMergeFlag==0
drop IncFlag
drop RawMergeFlag

* Merge in capacity and start year info
drop CapacityMW-UnitID
sort PlantID PrimeMover
merge m:1 PlantID PrimeMover using "`temp_3_1_plantprimemoverdata'"
keep if _merge==3
drop _merge

* Find the fuel type that is associated with the most MWh
bysort PlantID PrimeMover: egen MaxMWh = max(NetGenMWh)
gen NewFuel = ""
replace NewFuel = FuelType if NetGenMWh==MaxMWh
* Copy the predominant fuel type to the PlantID x PM group
gen NewFuel2 = ""
levelsof FuelType, local(fuellist)
foreach val of local fuellist {
	bysort PlantID PrimeMover: egen tag = max(inlist(NewFuel,"`val'"))
	replace NewFuel2 = "`val'" if tag==1
	drop tag
}
drop MaxMWh NewFuel

* Collapse to PlantID x PM
replace FuelType = NewFuel2
drop NewFuel2
sort PlantID PrimeMover FuelType
collapse (sum) TotalFuelmmBtu ElecFuelmmBtu NetGenMWh Emissions (mean) CapacityMW StartYear UnitID /*
	*/ , by(PlantID PrimeMover FuelType)
duplicates report PlantID PrimeMover	// no dupes

* Sort and save
sort PlantID PrimeMover FuelType
tempfile temp_nofuelmergegroup
save "`temp_nofuelmergegroup'"




********************************************************************************
* Append the "`temp_partialmergegroup'" and "`temp_nofuelmergegroup'" with
* the PlantID x PM x FuelType observations that match
use "`temp_rawmerge'", clear

* Drop PlantID x PM that do not match at all
sort PlantID PrimeMover
merge m:1 PlantID PrimeMover using "`temp_plantPMmergeflags'"
drop _merge
keep if PlantPMMerge==1
drop PlantPMMerge

* Keep PlantID x PM groups where all fuels merge
bysort PlantID PrimeMover: egen IncFlag = sd(RawMergeFlag)
replace IncFlag = 0 if IncFlag==.
replace IncFlag = 1 if IncFlag>0
keep if IncFlag==0 & RawMergeFlag==1
drop IncFlag
drop RawMergeFlag

* Append units that match on PlantID x PM but not FuelType
append using "`temp_partialmergegroup'"
append using "`temp_nofuelmergegroup'"

* Sort and save
sort PlantID PrimeMover FuelType
tempfile temp_appendedgroup
save "`temp_appendedgroup'"

* Create dataset of average capacity:MWh ratio and start year, by prime mover and fuel type
* We'll use this dataset to infer capacity for PlantID x PM that do not match at all
* Consolidate fuel types first
gen FuelTypeC = FuelType
replace FuelTypeC = "Oil" if inlist(FuelType,"DFO","KER","JF","RFO","WO")
replace FuelTypeC = "NG" if inlist(FuelType,"BFG","NG","OG","PG","SG")
drop FuelType
sort PrimeMover FuelTypeC
collapse (mean) NetGenMWh CapacityMW StartYear, by(PrimeMover FuelTypeC)
gen Cap_MWh_ratio = CapacityMW / NetGenMWh
drop NetGenMWh CapacityMW
sort PrimeMover FuelTypeC
tempfile temp_avgcapratio
save "`temp_avgcapratio'"




********************************************************************************
* Deal with PlantID x PMs that do not match at all
use "`temp_rawmerge'", clear
tab FuelType

* Keep PlantID x PM that do not match at all
sort PlantID PrimeMover
merge m:1 PlantID PrimeMover using "`temp_plantPMmergeflags'"
drop _merge
keep if PlantPMMerge==0
drop PlantPMMerge RawMergeFlag

* Merge in capacity ratios
drop StartYear
gen FuelTypeC = FuelType
replace FuelTypeC = "Oil" if inlist(FuelType,"DFO","KER","JF","RFO","WO")
replace FuelTypeC = "NG" if inlist(FuelType,"BFG","NG","OG","PG","SG")
sort PrimeMover FuelTypeC
merge m:1 PrimeMover FuelTypeC using "`temp_avgcapratio'"	// no _merge==1
keep if _merge==3
drop _merge FuelTypeC

* Compute capacity
replace CapacityMW = NetGenMWh * Cap_MWh_ratio
drop Cap_MWh_ratio

* Sort and save
sort PlantID PrimeMover FuelType
replace UnitID = 1e6 + _n
tempfile temp_nomergegroup
save "`temp_nomergegroup'"




********************************************************************************
* Append together complete dataset; classify technologies
use "`temp_appendedgroup'", clear
append using "`temp_nomergegroup'"
egen TotMWh = sum(NetGenMWh)			// should match sum from unmerged 923
drop TotMWh
egen TotEmissions = sum(Emissions)  	// should match sum from unmerged 923
drop TotEmissions
duplicates report UnitID		// no dupes
order UnitID
sort UnitID
tempfile temp_completedata
save "`temp_completedata'"




********************************************************************************
* Merge in plant location info; classify technologies
use "`temp_raw923'", clear

* Get plantID level dataset of location info
keep PlantID PlantState NERCregion
duplicates drop
duplicates report PlantID	// no duplicates
sort PlantID
tempfile temp_locationdata
save "`temp_locationdata'"

* Merge locations into complete data
use "`temp_completedata'", clear
sort PlantID
merge m:1 PlantID using "`temp_locationdata'"
keep if _merge==3		// no _merge==1
drop _merge

* Classify technologies
tab FuelType PrimeMover
gen Tech = ""
replace Tech = "NGCC" if PrimeMover=="CC" & inlist(FuelType,"NG","OG","PG")
replace Tech = "NGCT" if inlist(PrimeMover,"GT","IC") & inlist(FuelType,"NG","OG","PG")
replace Tech = "NGST" if PrimeMover=="ST" & inlist(FuelType,"NG","OG","PG")
replace Tech = "Oil" if inlist(FuelType,"DFO","JF","KER","RFO","WO")
replace Tech = "Coal" if inlist(FuelType,"BIT","SUB","LIG","PC","RC","SGC","WC")
tab Tech

* Save final data
order UnitID PlantID PlantState NERCregion Tech PrimeMover FuelType
sort UnitID
saveold "$outdir/Merged_923_and_3_1_Generator.dta", version(14) replace




********************************************************************************
* Compute and export percent of MWh that is cogen
* First total MWh in final data
sum NetGenMWh
local MWhavg = `r(mean)'
local N = `r(N)'
local MWh = `MWhavg' * `N'

* Now go back to the original EIA 923 data
use "$outdir/EIA923.dta", clear
* Keep only lower 48
drop if inlist(PlantState,"AK","HI")
* Keep cogen
keep if inlist(EIAsectornum,3,5,7) | PlantID==10686
drop NAICS-EIAsectorname
* Keep only fossil fuel generators (and drop FuelType==SC which has no generation)
drop AERFuelType	// AERFuelType doesn't match 3_1_Generator, but FuelType does
keep if inlist(FuelType,"BIT","DFO","JF","KER","LIG","NG","OG") /*
	*/ | inlist(FuelType,"PC","PG","RC","RFO","SGC","SGP","SUB","WC","WO")
* Drop fuel cells, compressed air, and other prime movers ("other" is a small number of refineries)
drop if inlist(PrimeMover,"FC","CE","OT")
* Drop state fuel level increment
drop if PlantID==99999
* Compute cogen MWh
sum NetGenMWh
local CogenMWhavg = `r(mean)'
local CogenN = `r(N)'
local CogenMWh = `CogenMWhavg' * `CogenN'

* Compute percent of MWh that is cogen and write tex file
local CogenPct = round(`CogenMWh' / (`MWh' + `CogenMWh') * 100,0.1)
di(`CogenPct')
file open CogenTex using "$texdir/CogenPct.tex", write replace
file write CogenTex %2.1f (`CogenPct') %9s "\%"
file close CogenTex

// Close out the log file
log close
