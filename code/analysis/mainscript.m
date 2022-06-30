% mainscript.m
% Ryan Kellogg
% Created: 13 August, 2021


%{
Runs models for clean energy standard (CES) vs carbon tax (CT) simulations
%}


clear all

% Identify root directories for repo and box
S = pwd;
test = strcmp(S(end-13:end),'CESequivalence') + strcmp(S(end-13:end),'cesequivalence');
while test==0
    S = S(1:end-1);
    test = strcmp(S(end-13:end),'CESequivalence') + strcmp(S(end-13:end),'cesequivalence');
end
clear test
cd(S)
globals         % call path names in globals.m
clear S

% Set all paths
dirs.rdir = strcat(dropbox, '/RawData');
dirs.idir = strcat(dropbox, '/IntermediateData');
dirs.wdir = strcat(repodir, '/code/analysis');
dirs.odir = strcat(repodir, '/analysisoutput');
dirs.pdir = strcat(repodir, '/paper');
dirs.scratchdir = strcat(dropbox, '/scratch');

% Add all code files (including utilities) to matlab search path
addpath(genpath(dirs.wdir))



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Create "bubble plots" and get correlations between ongoing op costs and emissions rate
% And output correlations to single-number tex files for paper
% Start with baseline model
obj = GenModel(dirs);
[CorrAll, Corr100, CorrNonPeak] = bubbleOCCER(obj,dirs);
% Correlation between OOC and emissions rate, all generation
filestr = sprintf('/single_num_tex/OOC_ER_corrall_basegas.tex');
fid = fopen(strcat(dirs.pdir, filestr),'w');
fprintf(fid,'%8.2f', CorrAll);
fclose(fid);
% Correlation between OOC and emissions rate, OOC<=100
filestr = sprintf('/single_num_tex/OOC_ER_corr100_basegas.tex');
fid = fopen(strcat(dirs.pdir, filestr),'w');
fprintf(fid,'%8.2f', Corr100);
fclose(fid);
% Correlation between OOC and emissions rate, non-peakers
filestr = sprintf('/single_num_tex/OOC_ER_corrNP_basegas.tex');
fid = fopen(strcat(dirs.pdir, filestr),'w');
fprintf(fid,'%8.2f', CorrNonPeak);
fclose(fid);

% $6.00/mmBtu gas, without shift in generation from gas to coal
Pgas = 6;
obj = GenModel(dirs,Pgas);
[CorrAll, Corr100, CorrNonPeak] = bubbleOCCER(obj,dirs);
% Correlation between OOC and emissions rate, all generation
filestr = sprintf('/single_num_tex/OOC_ER_corrall_%1.2fgas.tex',obj.Pgas0);
fid = fopen(strcat(dirs.pdir, filestr),'w');
fprintf(fid,'%8.2f', CorrAll);
fclose(fid);
% Correlation between OOC and emissions rate, OOC<=100
filestr = sprintf('/single_num_tex/OOC_ER_corr100_%1.2fgas.tex',obj.Pgas0);
fid = fopen(strcat(dirs.pdir, filestr),'w');
fprintf(fid,'%8.2f', Corr100);
fclose(fid);
% Correlation between OOC and emissions rate, non-peakers
filestr = sprintf('/single_num_tex/OOC_ER_corrNP_%1.2fgas.tex',obj.Pgas0);
fid = fopen(strcat(dirs.pdir, filestr),'w');
fprintf(fid,'%8.2f', CorrNonPeak);
fclose(fid);

% $6.00/mmBtu gas, with shift in generation from gas to coal
Pgas = 6;
obj = GenModel_GasCoal(dirs,Pgas);
[CorrAll_gc, Corr100_gc, CorrNonPeak_gc] = bubbleOCCER(obj,dirs);
% Correlation between OOC and emissions rate, all generation
filestr = sprintf('/single_num_tex/OOC_ER_corrall_%1.2fgas_gc.tex',obj.Pgas0);
fid = fopen(strcat(dirs.pdir, filestr),'w');
fprintf(fid,'%8.2f', CorrAll_gc);
fclose(fid);
% Correlation between OOC and emissions rate, OOC<=100
filestr = sprintf('/single_num_tex/OOC_ER_corr100_%1.2fgas_gc.tex',obj.Pgas0);
fid = fopen(strcat(dirs.pdir, filestr),'w');
fprintf(fid,'%8.2f', Corr100_gc);
fclose(fid);
% Correlation between OOC and emissions rate, non-peakers
filestr = sprintf('/single_num_tex/OOC_ER_corrNP_%1.2fgas_gc.tex',obj.Pgas0);
fid = fopen(strcat(dirs.pdir, filestr),'w');
fprintf(fid,'%8.2f', CorrNonPeak_gc);
fclose(fid);



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Simulate outcomes under CES and CT, for baseline 2019 fuel prices
% Instantiate model
obj = GenModel_GasCoal(dirs);
% Simulate full model
[EmitPathCES, GenPathCES, CostPathCES, SBPathCES,...
    EmitPathCT, GenPathCT, CostPathCT, TotTaxPathCT, TotTaxNoPeakPathCT, TaxRatePathCT,...
    SBPathCT, ElecPricePathCES, ElecPricePathZES, ElecPricePathCT,...
    TotEmitCES, TotEmitCESNoPeak, TotEmitCT, TotEmitCTNoPeak, DiffTotEmit, PctEmissionsIncreaseCES,...
    TotCostCES, TotCostCT, DiffTotCost, PctCostIncreaseCT, TotTaxCT, TotTaxNoPeakCT,...
    TotSBCES, TotSBCT] = AllResults(obj);

% Repeat for model without coal-to-gas shift in response to CT
obj_noGC = GenModel(dirs);
% Simulate full model
[EmitPathCES_noGC, GenPathCES_noGC, CostPathCES_noGC, SBPathCES_noGC,...
        EmitPathCT_noGC, GenPathCT_noGC, CostPathCT_noGC, TotTaxPathCT_noGC, TotTaxNoPeakPathCT_noGC, TaxRatePathCT_noGC,...
        SBPathCT_noGC, ElecPricePathCES_noGC, ElecPricePathZES_noGC, ElecPricePathCT_noGC,...
        TotEmitCES_noGC, TotEmitCESNoPeak_noGC, TotEmitCT_noGC, TotEmitCTNoPeak_noGC, DiffTotEmit_noGC, PctEmissionsIncreaseCES_noGC,...
        TotCostCES_noGC, TotCostCT_noGC, DiffTotCost_noGC, PctCostIncreaseCT_noGC, TotTaxCT_noGC, TotTaxNoPeakCT_noGC,...
        TotSBCES_noGC, TotSBCT_noGC] = AllResults(obj_noGC);

% Plots
% Plot % decrease in emissions vs % decrease in fossil MWh, ignoring peakers
FossilShareDecrease = plotemissions(obj,dirs,EmitPathCT,EmitPathCES);   % with coal-gas shifting
FossilShareDecrease_noGC = plotemissions(obj_noGC,dirs,EmitPathCT_noGC,EmitPathCES_noGC);   % without
% Plot carbon tax path
dummy = plottaxrate(obj,dirs,FossilShareDecrease,TaxRatePathCT);
% Plot carbon tax revenue
dummy = plottaxrev(obj,dirs,FossilShareDecrease,TotTaxNoPeakPathCT);
% Plot wholesale electricity prices
dummy = plotelecprice(obj,dirs,ElecPricePathCT,ElecPricePathCES,ElecPricePathZES);
% Change in social surplus
SBIncreasePct = plotSB(obj,dirs,SBPathCT,SBPathCES);

% Output single number tex files for paper
% $/MWh cutoff for peakers
filestr = sprintf('/single_num_tex/PeakerCost_basegas.tex');
fid = fopen(strcat(dirs.pdir, filestr),'w');
fprintf(fid,'$\\$ %8.0f $', obj.ZEcost);
fclose(fid);
% max $/MWh for peakers
filestr = sprintf('/single_num_tex/PeakerMaxCost_basegas.tex');
fid = fopen(strcat(dirs.pdir, filestr),'w');
fprintf(fid,'$\\$ %8.0f $', obj.ZEcostMax);
fclose(fid);
% Percent of emissions from peakers
filestr = sprintf('/single_num_tex/PeakerEmissionsShare.tex');
fid = fopen(strcat(dirs.pdir, filestr),'w');
fprintf(fid,'%8.1f\\%%', obj.PeakEmit / obj.TotEmitAll * 100);
fclose(fid);
% Percent increase in total emissions under CES
filestr = sprintf('/single_num_tex/PctIncreaseEmissionsCES_basegas.tex');
fid = fopen(strcat(dirs.pdir, filestr),'w');
fprintf(fid,'%8.1f\\%%', PctEmissionsIncreaseCES);
fclose(fid);
% Percent increase in total emissions under CES w/o coal-gas shift
filestr = sprintf('/single_num_tex/PctIncreaseEmissionsCES_basegas_nocoalgas.tex');
fid = fopen(strcat(dirs.pdir, filestr),'w');
fprintf(fid,'%8.1f\\%%', PctEmissionsIncreaseCES_noGC);
fclose(fid);
% Total tax revenue, $ billion, not including peakers
filestr = sprintf('/single_num_tex/TotTaxRevNP_basegas.tex');
fid = fopen(strcat(dirs.pdir, filestr),'w');
fprintf(fid,'$\\$ %8.0f $', TotTaxNoPeakCT/1e9);
fclose(fid);
% Baseline fuel prices, $/mmBtu
filestr = sprintf('/single_num_tex/BaseGasPrice.tex');
fid = fopen(strcat(dirs.pdir, filestr),'w');
fprintf(fid,'$\\$ %8.2f $', obj.Pgas0);
fclose(fid);
filestr = sprintf('/single_num_tex/BaseCoalPrice.tex');
fid = fopen(strcat(dirs.pdir, filestr),'w');
fprintf(fid,'$\\$ %8.2f $', obj.Pcoal0);
fclose(fid);
filestr = sprintf('/single_num_tex/BaseOilPrice.tex');
fid = fopen(strcat(dirs.pdir, filestr),'w');
fprintf(fid,'$\\$ %8.2f $', obj.Poil0);
fclose(fid);
% Peaker share
filestr = sprintf('/single_num_tex/PeakerShare.tex');
fid = fopen(strcat(dirs.pdir, filestr),'w');
fprintf(fid,'%8.0f\\%%', obj.PeakShare*100);
fclose(fid);
% Share of generation >$100/MWh
OOC = CalcOOC(obj,0);
ExpensiveMWh = sum(obj.dataGen(OOC>100));
ExpensiveShare = ExpensiveMWh / sum(obj.dataGen);
filestr = sprintf('/single_num_tex/ExpensiveShare_basegas.tex');
fid = fopen(strcat(dirs.pdir, filestr),'w');
fprintf(fid,'%8.1f\\%%', ExpensiveShare*100);
fclose(fid);
% Number of units
filestr = sprintf('/single_num_tex/Nunits.tex');
fid = fopen(strcat(dirs.pdir, filestr),'w');
fprintf(fid,'%8.0f', obj.N);
fclose(fid);
% Percent increase in social surplus under CT vs CES
filestr = sprintf('/single_num_tex/PctIncreaseSocialSurplus_CT_basegas.tex');
fid = fopen(strcat(dirs.pdir, filestr),'w');
fprintf(fid,'%8.1f\\%%', SBIncreasePct);
fclose(fid);
% Percent of coal generation that shifts to gas in response to a $1/tonne increase in the carbon tax
% For taxes up to $20/tonne tax
filestr = sprintf('/single_num_tex/PctCoalShift_20tax.tex');
fid = fopen(strcat(dirs.pdir, filestr),'w');
fprintf(fid,'%8.2f\\%%', obj.PropSwitch20/20*100);
fclose(fid);
% For taxes greater than $70/tonne
filestr = sprintf('/single_num_tex/PctCoalShift_70tax.tex');
fid = fopen(strcat(dirs.pdir, filestr),'w');
fprintf(fid,'%8.2f\\%%', (obj.PropSwitch70-obj.PropSwitch20)/50*100);
fclose(fid);



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Simulate outcomes under CES and CT, for $6 gas
Pgas = 6;
% Instantiate model
obj = GenModel_GasCoal(dirs,Pgas);
% Simulate full model
[EmitPathCES, GenPathCES, CostPathCES, SBPathCES,...
    EmitPathCT, GenPathCT, CostPathCT, TotTaxPathCT, TotTaxNoPeakPathCT, TaxRatePathCT,...
    SBPathCT, ElecPricePathCES, ElecPricePathZES, ElecPricePathCT,...
    TotEmitCES, TotEmitCESNoPeak, TotEmitCT, TotEmitCTNoPeak, DiffTotEmit, PctEmissionsIncreaseCES,...
    TotCostCES, TotCostCT, DiffTotCost, PctCostIncreaseCT, TotTaxCT, TotTaxNoPeakCT,...
    TotSBCES, TotSBCT] = AllResults(obj);

% Plots
% Plot % decrease in emissions vs % decrease in fossil MWh, ignoring peakers
FossilShareDecrease = plotemissions(obj,dirs,EmitPathCT,EmitPathCES);
% Plot carbon tax path
dummy = plottaxrate(obj,dirs,FossilShareDecrease,TaxRatePathCT);
% Plot carbon tax revenue
dummy = plottaxrev(obj,dirs,FossilShareDecrease,TotTaxNoPeakPathCT);
% Plot wholesale electricity prices
dummy = plotelecprice(obj,dirs,ElecPricePathCT,ElecPricePathCES,ElecPricePathZES);
% Change in social surplus
SBIncreasePct = plotSB(obj,dirs,SBPathCT,SBPathCES);

% Output single number tex files for paper
% Percent increase in total emissions under CES
filestr = sprintf('/single_num_tex/PctIncreaseEmissionsCES_%1.2fgas.tex',obj.Pgas0);
fid = fopen(strcat(dirs.pdir, filestr),'w');
fprintf(fid,'%8.1f\\%%', PctEmissionsIncreaseCES);
fclose(fid);
% Total tax revenue, $ billion, not including peakers
filestr = sprintf('/single_num_tex/TotTaxRevNP_%1.2fgas.tex',obj.Pgas0);
fid = fopen(strcat(dirs.pdir, filestr),'w');
fprintf(fid,'$\\$ %8.0f $', TotTaxNoPeakCT/1e9);
fclose(fid);
% Share of generation >$100/MWh
OOC = CalcOOC(obj,0);
ExpensiveMWh = sum(obj.dataGen(OOC>100));
ExpensiveShare = ExpensiveMWh / sum(obj.dataGen);
filestr = sprintf('/single_num_tex/ExpensiveShare_%1.2fgas.tex',obj.Pgas0);
fid = fopen(strcat(dirs.pdir, filestr),'w');
fprintf(fid,'%8.1f\\%%', ExpensiveShare*100);
fclose(fid);
% Percent increase in social surplus under CT vs CES
filestr = sprintf('/single_num_tex/PctIncreaseSocialSurplus_CT_%1.2fgas.tex',obj.Pgas0);
fid = fopen(strcat(dirs.pdir, filestr),'w');
fprintf(fid,'%8.1f\\%%', SBIncreasePct);
fclose(fid);
% Percent increase in coal generation at baseline from gas price change
filestr = sprintf('/single_num_tex/PctCoalInc_%1.2fgas.tex',obj.Pgas0);
fid = fopen(strcat(dirs.pdir, filestr),'w');
fprintf(fid,'%8.1f\\%%', -obj.CoalShareSwitch*100);
fclose(fid);



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Sensitivity to different endpoint values for R, for baseline 2019 fuel prices
% Instantiate model at R = $70/MWh at full decarbonization
obj = GenModel_GasCoal(dirs,0,70);
% Simulate full model
[EmitPathCES, GenPathCES, CostPathCES, SBPathCES,...
    EmitPathCT, GenPathCT, CostPathCT, TotTaxPathCT, TotTaxNoPeakPathCT, TaxRatePathCT,...
    SBPathCT, ElecPricePathCES, ElecPricePathZES, ElecPricePathCT,...
    TotEmitCES, TotEmitCESNoPeak, TotEmitCT, TotEmitCTNoPeak, DiffTotEmit, PctEmissionsIncreaseCES,...
    TotCostCES, TotCostCT, DiffTotCost, PctCostIncreaseCT, TotTaxCT, TotTaxNoPeakCT,...
    TotSBCES, TotSBCT] = AllResults(obj);
% Output results
% Percent increase in total emissions under CES
filestr = sprintf('/single_num_tex/PctIncreaseEmissionsCES_basegas_R70.tex');
fid = fopen(strcat(dirs.pdir, filestr),'w');
fprintf(fid,'%8.1f\\%%', PctEmissionsIncreaseCES);
fclose(fid);
% Total tax revenue, $ billion, not including peakers
filestr = sprintf('/single_num_tex/TotTaxRevNP_basegas_R70.tex');
fid = fopen(strcat(dirs.pdir, filestr),'w');
fprintf(fid,'$\\$ %8.0f $', TotTaxNoPeakCT/1e9);
fclose(fid);

% Instantiate model at R = $110/MWh at full decarbonization
obj = GenModel_GasCoal(dirs,0,110);
% Simulate full model
[EmitPathCES, GenPathCES, CostPathCES, SBPathCES,...
    EmitPathCT, GenPathCT, CostPathCT, TotTaxPathCT, TotTaxNoPeakPathCT, TaxRatePathCT,...
    SBPathCT, ElecPricePathCES, ElecPricePathZES, ElecPricePathCT,...
    TotEmitCES, TotEmitCESNoPeak, TotEmitCT, TotEmitCTNoPeak, DiffTotEmit, PctEmissionsIncreaseCES,...
    TotCostCES, TotCostCT, DiffTotCost, PctCostIncreaseCT, TotTaxCT, TotTaxNoPeakCT,...
    TotSBCES, TotSBCT] = AllResults(obj);
% Output results
% Percent increase in total emissions under CES
filestr = sprintf('/single_num_tex/PctIncreaseEmissionsCES_basegas_R110.tex');
fid = fopen(strcat(dirs.pdir, filestr),'w');
fprintf(fid,'%8.1f\\%%', PctEmissionsIncreaseCES);
fclose(fid);
% Total tax revenue, $ billion, not including peakers
filestr = sprintf('/single_num_tex/TotTaxRevNP_basegas_R110.tex');
fid = fopen(strcat(dirs.pdir, filestr),'w');
fprintf(fid,'$\\$ %8.0f $', TotTaxNoPeakCT/1e9);
fclose(fid);



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Loop over gas prices and simulate excess emissions
PGasVec = [2:0.2:6]';              % vector of gas prices to loop over
NPG = length(PGasVec);
CorrNonPeakVec = zeros(NPG,1);      % initialize
ExcessEmitVec = zeros(NPG,1);
for i = 1:NPG
    Pgas = PGasVec(i);
    obji = GenModel_GasCoal(dirs,Pgas);
    [~, ~, CorrNonPeaki] = bubbleOCCER(obji,dirs,1);
    [~, ~, ~, ~,...
        ~, ~, ~, ~, ~, ~,...
        ~, ~, ~, ~,...
        ~, ~, ~, ~, ~, PctEmissionsIncreaseCESi,...
        ~, ~, ~, ~, ~, ~,...
        ~, ~] = AllResults(obji);
    CorrNonPeakVec(i) = CorrNonPeaki;
    ExcessEmitVec(i) = PctEmissionsIncreaseCESi;
end

% Make vertically stacked plot
Ylabels = ["",""];
clf
s = stackedplot(PGasVec,[CorrNonPeakVec ExcessEmitVec],"DisplayLabels",Ylabels,'LineWidth',2.5);
s.AxesProperties(1).YLimits = [-0.8 1];
s.AxesProperties(2).YLimits = [0 45];
xlabel('Natural gas price, $/mmBtu');
grid
h = gcf;
set(gca,'FontSize',20);
set(h,'PaperOrientation','landscape');
set(h,'PaperUnits','normalized');
set(h,'PaperPosition', [0 0 1 1]);
% Save plot
filestr = sprintf('/figures_slides/StackedPlot_vs_Pgas.pdf');
outfile = strcat(dirs.pdir, filestr);
print(h,outfile,'-dpdf');
% Plot formatted for paper
Ylabels = ["Correlation","Excess emissions (%)"];
clf
s = stackedplot(PGasVec,[CorrNonPeakVec ExcessEmitVec],"DisplayLabels",Ylabels,'LineWidth',2.5);
s.AxesProperties(1).YLimits = [-0.8 1];
s.AxesProperties(2).YLimits = [0 45];
xlabel('Natural gas price, $/mmBtu');
grid
h = gcf;
set(gca,'FontName','Times New Roman');
set(gca,'FontSize',20);
set(h,'PaperOrientation','landscape');
set(h,'PaperUnits','normalized');
set(h,'PaperPosition', [0 0 1 1]);
filestr = sprintf('/figures/StackedPlot_vs_Pgas.pdf');
outfile = strcat(dirs.pdir, filestr);
print(h,outfile,'-dpdf');


