% Superclass that instantiates the GenModel object 
classdef GenModel
properties
    % List of all properties attached to the model object
    AgeFactor
    BaseYear
    EndYear
    NT
    Pgas0
    Pcoal0
    Poil0
    Pgasmax
    dataID
    dataGen
    dataHR
    dataER
    dataEmit
    dataCap
    dataStart
    dataVarOM
    dataFixedOM
    dataCapex
    dataNERC
    dataTech
    N
    NNP
    Peaker
    NPGen
    NPER
    NPEmit
    PeakShare
    TotMWhAll
    TotEmitAll
    PeakMWh
    ZEcost
    ZEcostMax
    ZEcostSlope
    ZEcostYr
    PeakEmit
    DirtyMWhYr
    SCC
end
methods
%% Constructor
function obj = GenModel(dirs,PGasIn,Rfinal)
    % Inputs:
    % dirs: directory struct
    % PGasIn: optional manual input of natural gas price ($/mmBtu)
    % Rfinal: $/MWh for zero-emission power at full decarbonization ($/MWh)

    % Load fixed parameters from the Input_Parameters.csv file
    inputparamsfile = strcat(dirs.rdir,'/Input_Parameters.csv');
    inputparams = readmatrix(inputparamsfile,'Range',[1 2]);
    obj.AgeFactor = inputparams(1);     % age factor for capex calcs
    obj.BaseYear = inputparams(2);      % baseline year
    obj.Pgas0 = inputparams(3);         % gas price in baseline year (all prices $/mmBtu)
    obj.Pcoal0 = inputparams(4);        % coal price in baseline year
    obj.Poil0 = inputparams(5);         % oil price in baseline year

    % Replace gas price if manually input
    if nargin>=2 && PGasIn>0
        obj.Pgas0 = PGasIn;
    else
    end

    % Maximum natural gas price to consider
    % Set of peaker units will be determined using this price
    obj.Pgasmax = 6;

    % Set share of MWh to designate as peakers or local reliability
    % These will not be displaced by zero emission sources
    PeakerShare = 0.1;      % will be adjusted slightly upward later to designate whole units

    % Load and parse numeric unit-level data
    gendatafile = strcat(dirs.idir,'/EIAdata/UnitNumericData.csv');
    gendata = readmatrix(gendatafile);
    obj.dataID = gendata(:,1);      % unique unit IDs
    obj.dataGen = gendata(:,3);     % elec generation in MWh
    obj.dataHR = gendata(:,2) ./ obj.dataGen;   % heat rate in mmBtu / MWh
    obj.dataER = gendata(:,7);      % CO2 emissions rate in metric ton CO2 / MWh
    obj.dataEmit = obj.dataGen .* obj.dataER;   % CO2 emissions
    obj.dataCap = gendata(:,5);     % capacity in MW
    obj.dataStart = gendata(:,6);   % start date in calendar years
    obj.dataVarOM = gendata(:,8);   % variable O&M in $/MWh
    obj.dataFixedOM = gendata(:,9); % fixed O&M in $/kW
    obj.dataCapex = gendata(:,10);  % annual ongoing capex in $/kW
    obj.N = length(obj.dataID);     % number of units

    % Load and parse string unit-level data
    genstrfile = strcat(dirs.idir,'/EIAdata/UnitStringData.csv');
    genstr = readmatrix(genstrfile,'OutputType','string');
    % Check unit ID match
    tempID = str2double(genstr(:,1));
    test = obj.dataID==tempID;
    test = min(test);
    if min(test)==0         % mismatch
        error('Error. Unit IDs in UnitNumericData.csv and UnitStringData.csv do not match.')
    else
    end
    obj.dataNERC = genstr(:,4);     % NERC region
    obj.dataTech = genstr(:,5);     % fuel type

    % Compute total generation and total non-peaker generation
    obj.TotMWhAll = sum(obj.dataGen);               % total MWh generated over all generators
    obj.TotEmitAll = sum(obj.dataGen.*obj.dataER);  % total emissions
    PeakerMWh = obj.TotMWhAll * PeakerShare;        % peaker MWh if marginal unit is divisible
    NonPeakMWh = obj.TotMWhAll - PeakerMWh;         % non-peaker MWh if marginal unit is divisible

    % Get the zero-emission cost per MWh that leads to NonPeakMwh being out of merit at
    % a gas price of obj.Pgasmax. Also get OOC for all units at this price
    objmax = obj;
    objmax.Pgas0 = objmax.Pgasmax;      % set gas price equal to Pgasmax
    [obj.ZEcost, OOC] = CalcCostCutoffPeaker(objmax,NonPeakMWh,0);

    % Flag peaker units
    obj.Peaker = OOC>obj.ZEcost;
    obj.NNP = obj.N - sum(obj.Peaker);  % number of non-peaker units

    % Generation, emissions rates, and emissions for non-peakers only
    obj.NPGen = obj.dataGen(~obj.Peaker);
    obj.NPER = obj.dataER(~obj.Peaker);
    obj.NPEmit = obj.dataEmit(~obj.Peaker);

    % Get generation and emissions from peakers (now treating peakers as whole units)
    obj.PeakMWh = sum(obj.dataGen(obj.Peaker));
    obj.PeakEmit = sum(obj.dataEmit(obj.Peaker));
    obj.PeakShare = obj.PeakMWh / obj.TotMWhAll;        % will be slightly higher than PeakerShare

    % Define end of simulation and DirtyMWh (excluding peakers) each year
    obj.EndYear = 2035;     % all dirty gone by this date
    obj.NT = obj.EndYear - obj.BaseYear + 1; % number of years including baseline
    % evenly spaced decrease in dirty MWh
    obj.DirtyMWhYr = linspace(obj.TotMWhAll-obj.PeakMWh,0,obj.NT)';

    % Marginal $/MWh cost of zero emissions energy at full decarbonization (apart from peakers)
    % Use input if provided. Otherwise use LBNL estimate.
    if nargin==3 && Rfinal>obj.ZEcost
        obj.ZEcostMax = Rfinal;
    else
        ZEcostadd = 26.80;  % increase in costs from no new clean energy to full decarb (per LBNL)
        obj.ZEcostMax = obj.ZEcost + ZEcostadd;
    end

    % Get marginal cost of zero emissions generation associated with each step of DirtyMWhYr
    obj.ZEcostSlope = (obj.ZEcostMax - obj.ZEcost) / max(obj.DirtyMWhYr);
    obj.ZEcostYr = obj.ZEcost + obj.ZEcostSlope * (max(obj.DirtyMWhYr) - obj.DirtyMWhYr);

    % Social cost of carbon
    obj.SCC = 200;      % $/tonne
end



%% Compute ongoing op cost for each generator, given simulation year
function OOC = CalcOOC(obj,t)
    % Inputs:
    % t: index year for simulation (calendar year is obj.BaseYear + t)

    % Outputs:
    % OOC: N vector of total private cost

    % Get relevant fuel price
    Price = repmat(obj.Pgas0,obj.N,1);          % initialize with gas price
    Price(obj.dataTech=="Coal") = obj.Pcoal0;   % coal units
    Price(obj.dataTech=="Oil") = obj.Poil0;     % oil units

    % Total variable costs, $/MWh
    TVC = Price .* obj.dataHR + obj.dataVarOM;

    % Age effects for ongoing capex. Coal units only. $/kW
    y = obj.BaseYear + t;       % calendar year
    AgeCost = zeros(obj.N,1);   % initialize
    AgeCost(obj.dataTech=="Coal") = obj.AgeFactor...
        * (y - obj.dataStart(obj.dataTech=="Coal"));

    % Compute OOC
    FCperMWh = (obj.dataFixedOM + obj.dataCapex + AgeCost)...
        .* obj.dataCap * 1000 ./ obj.dataGen;
    OOC = TVC + FCperMWh;
end



%% Compute private cost cutoff for non-peaker units
function [CostCutoff, OOC] = CalcCostCutoffPeaker(obj,NonPeakMWh,t)
    % Inputs:
    % NonPeakMWh: total MWh of fossil that is not designated as peaker
    % t: index year for simulation (calendar year is obj.BaseYear + t)

    % Outputs:
    % CostCutoff: $/MWh for highest-cost remaining fossil plant that runs 100%
    % OOC: ongoing operating cost for each plant in year t
    
    OOC = CalcOOC(obj,t);           % ongoing op costs for each unit in year t
    if NonPeakMWh==0
        CostCutoff = 0;             % no dirty left
    else
        [sortOOC, I] = sort(OOC);   % sorted OOC
        sortGen = obj.dataGen(I);   % sorted generation
        cumGen = cumsum(sortGen);   % cumulative generation
        CostCutoff = max(sortOOC(cumGen<NonPeakMWh));     % highest cost fossil unit fully producing, $/MWh
    end
end



%% Compute private cost cutoff assoicated with a CES policy leaving behind some amount of dirty gen
function [CostCutoff, CostCutoff2, OOC, OOCall] = CalcCostCutoffCES(obj,DirtyMWh,t)
    % Inputs:
    % DirtyMWh: total MWh of fossil still producing after imposition of CES (not including peakers)
    % t: index year for simulation (calendar year is obj.BaseYear + t)

    % Outputs:
    % CostCutoff: $/MWh for highest-cost remaining fossil plant that runs 100%
    % CostCutoff2: $/MWh for plant right on the margin
    % OOC: ongoing operating cost for each non-peaker plant in year t
    % OOCall: ongoing operating cost for all plants (incl peaker) in year t
    
    OOCall = CalcOOC(obj,t);        % ongoing op costs for all units (incl peakers) in year t
    OOC = OOCall(~obj.Peaker);      % non-peakers only
    if DirtyMWh==0
        CostCutoff = 0; CostCutoff2 = 0;    % no dirty left
    else
        [sortOOC, I] = sort(OOC);   % sorted OOC
        sortGen = obj.NPGen(I);     % sorted generation
        cumGen = cumsum(sortGen);   % cumulative generation
        CostCutoff = max(sortOOC(cumGen<DirtyMWh));     % highest cost fossil unit fully producing, $/MWh
        % Find cost cutoff for plant right on the margin
        Ind = find(sortOOC==CostCutoff);
        if Ind==obj.NNP
            CostCutoff2 = sortOOC(obj.NNP);
        else
            CostCutoff2 = sortOOC(Ind+1);
        end
    end
end



%% Compute emissions, fossil gen, and private costs imposed by a particular CES in a given year
function [TotEmit, TotGen, CostImposed, ElecPrice, ElecPriceZES] = CEScalc(obj,DirtyMWh,t)
    % Inputs:
    % DirtyMWh: total MWh of fossil still producing after imposition of CES (not including peakers)
    % t: index year for simulation (calendar year is obj.BaseYear + t)

    % Outputs:
    % TotEmit: total CO2 emissions from remaining fossil (incl peakers)
    % TotGen: total generation from remaining fossil (incl peaker)
    % CostImposed: private cost of CES
    % ElecPrice: wholesale electricity price in $/MWh, assuming revenue-neutral CES
    % ElecPriceZES: wholesale electricity price in $/MWh, under ZES
    
    % Get cost cutoff and ongoing op cost for all units
    [CostCutoff, CostCutoff2, OOC, OOCall] = CalcCostCutoffCES(obj,DirtyMWh,t);

    % Marginal cost of zero emissions energy
    ZEcostmarg = obj.ZEcostYr(t+1);

    % Total fossil cost, all units and summed
    FossilCostsAll = OOCall .* obj.dataGen;         % total private cost for each unit
    TotCostAll = sum(FossilCostsAll);               % summed
    TotCostPeak = sum(FossilCostsAll(obj.Peaker));  % peakers only
    FossilCosts = OOC .* obj.NPGen;                 % total private cost for each non-peaker

    % Index of marginal unit (among non-peakers)
    Ind = find(OOC==CostCutoff2);

    % Total fossil emissions, gen, and costs after the policy (including non-displaced peakers)
    if DirtyMWh==0
        TotEmit = obj.PeakEmit; TotGen = obj.PeakMWh; TotCost = TotCostPeak;
    elseif DirtyMWh>=obj.TotMWhAll - obj.PeakMWh
        TotEmit = obj.TotEmitAll; TotGen = obj.TotMWhAll; TotCost = TotCostAll;
    else
        TotGen = DirtyMWh + obj.PeakMWh;
        GenMarg = DirtyMWh - sum(obj.NPGen(OOC<=CostCutoff));   % gen from marginal unit
        EmitMarg = GenMarg * obj.NPER(Ind);                     % emissions from marginal unit
        CostMarg = GenMarg * CostCutoff2;                       % cost from marginal unit
        TotEmit = sum(obj.NPEmit(OOC<=CostCutoff)) + EmitMarg + obj.PeakEmit;
        TotCost = sum(FossilCosts(OOC<=CostCutoff)) + CostMarg + TotCostPeak;
    end

    % Total cost imposed
    CleanMWh = obj.TotMWhAll - TotGen;
    CleanCost = CleanMWh * (obj.ZEcost + ZEcostmarg) / 2;   % cost of clean gen
    CostImposed = CleanCost - (TotCostAll - TotCost);       % change in private cost

    % Electricity price, assuming revenue-neutral CES
    % Will be weighted average marginal cost of clean and dirty
    ElecPrice = (ZEcostmarg*CleanMWh + CostCutoff2*DirtyMWh) / (CleanMWh + DirtyMWh);

    % Electricity price under ZES is the OOC of the marginal fossil unit
    if DirtyMWh==0
        ElecPriceZES = min(OOC);        % min OOC rather than zero
    else
        ElecPriceZES = CostCutoff2;
    end
end



%% Simulate emissions, generation, and private costs over CES transition
function [EmitPath, GenPath, CostPath, ElecPricePath, ElecPricePathZES, SBPath] = SimCES(obj)
    % Outputs:
    % EmitPath: total CO2 emissions from remaining fossil (incl peakers) by year
    % GenPath: total generation from remaining fossil (incl peakers) by year
    % CostPath: private cost of CES, by year
    % ElecPricePath: wholesale price per MWh under CES, by year
    % ElecPriceZESPath: wholesale price per MWh under ZES, by year
    % SBPath: Social benefits of CES, by year

    % initialize output
    EmitPath = zeros(obj.NT,1); GenPath = zeros(obj.NT,1); CostPath = zeros(obj.NT,1);
    ElecPricePath = zeros(obj.NT,1); ElecPricePathZES = zeros(obj.NT,1); SBPath = zeros(obj.NT,1);
    for s = 0:obj.NT-1
        t = s + 1;      % years since baseline
        [EmitPath(t), GenPath(t), CostPath(t), ElecPricePath(t), ElecPricePathZES(t)]...
            = CEScalc(obj,obj.DirtyMWhYr(t),s);
        SBPath(t) = (obj.TotEmitAll - EmitPath(t)) * obj.SCC - CostPath(t);
    end
end



%% Compute tax cutoff assoicated with a carbon tax policy leaving behind some amount of dirty gen
function [TaxCutoff, TaxCutoff2, OOC, OOCall, CritTax] = CalcCostCutoffCT(obj,DirtyMWh,t)
    % Inputs:
    % DirtyMWh: total MWh of fossil still producing after imposition of CT (not including peakers)
    % t: index year for simulation (calendar year is obj.BaseYear + t)

    % Outputs:
    % TaxCutoff: critical tax rate for last fossil plant that runs 100%
    % TaxCutoff2: critical tax rate for fossil plant right on the margin
    % OOC: ongoing operating cost for each non-peaker plant in year t
    % OOCall: ongoing operating cost for all plants (incl peaker) in year t
    % CritTax: NNP-vector of unit-level critical carbon tax such that 
        % the ongoing cost of each unit is at least obj.ZEcost
    
    OOCall = CalcOOC(obj,t);        % ongoing op costs for all units (incl peakers) in year t
    OOC = OOCall(~obj.Peaker);      % non-peakers only
    
    ZEcostmarg = obj.ZEcostYr(t+1); % Marginal cost of zero emissions energy

    % Compute critical carbon tax such that ongoing cost of each unit is at least ZEcostmarg
    CritTax = (ZEcostmarg - OOC) ./ obj.NPER;
    CritTax(CritTax<0) = 0;         % units with priv costs > ZEcostmarg

    if DirtyMWh>=obj.TotMWhAll - obj.PeakMWh
        TaxCutoff = 0; TaxCutoff2 = 0;                          % no tax needed
    elseif DirtyMWh==0
        TaxCutoff = max(CritTax); TaxCutoff2 = max(CritTax);    % maximal tax
    else
        [sortTax, I] = sort(CritTax,'descend');     % sorted critical tax
        sortGen = obj.NPGen(I);                     % sorted generation
        cumGen = cumsum(sortGen);                   % cumulative generation
        TaxCutoff = min(sortTax(cumGen<DirtyMWh));  % lowest critical tax fossil unit fully producing
        % Find tax cutoff for plant right on the margin
        Ind = find(sortTax==TaxCutoff);
        if Ind==obj.NNP
            TaxCutoff2 = sortTax(obj.NNP);
        else
            TaxCutoff2 = sortTax(Ind+1);
        end
    end
end



%% Compute emissions, private costs, and taxes imposed by a particular carbon tax in a given year
function [TotEmit, TotGen, CostImposed, TotTax, TotTaxNoPeak, TaxRate, ElecPrice]...
        = Taxcalc(obj,DirtyMWh,t)
    % Inputs:
    % DirtyMWh: total MWh of fossil still producing after imposition of CT (not including peakers)
    % t: index year for simulation (calendar year is obj.BaseYear + t)

    % Outputs:
    % TotEmit: total CO2 emissions from remaining fossil (incl peakers)
    % TotGen: total generation from remaining fossil (incl peaker)
    % CostImposed: private cost of CT
    % TotTax: total tax collected
    % TotTaxNoPeak: total tax collected from non-peakers
    % TaxRate: tax in $/mton
    % ElecPrice: wholesale electricity price in $/MWh
    
    % Get tax cutoff, ongoing op cost, and critical tax for all units
    [TaxCutoff, TaxCutoff2, OOC, OOCall, CritTax] = CalcCostCutoffCT(obj,DirtyMWh,t);
    TaxRate = TaxCutoff2;

    % Marginal cost of zero emissions energy
    ZEcostmarg = obj.ZEcostYr(t+1);

    % Total fossil cost, all units and summed
    FossilCostsAll = OOCall .* obj.dataGen;         % total private cost for each unit
    TotCostAll = sum(FossilCostsAll);               % summed
    TotCostPeak = sum(FossilCostsAll(obj.Peaker));  % peakers only
    FossilCosts = OOC .* obj.NPGen;                 % total private cost for each non-peaker

    % Index of marginal unit
    Ind = find(CritTax==TaxCutoff2);

    % Total emissions and gen after the policy (including non-displaced peakers)
    if DirtyMWh==0
        TotEmit = obj.PeakEmit; TotGen = obj.PeakMWh; TotCost = TotCostPeak;
    elseif DirtyMWh>=obj.TotMWhAll - obj.PeakMWh
        TotEmit = obj.TotEmitAll; TotGen = obj.TotMWhAll; TotCost = TotCostAll;
    else
        TotGen = DirtyMWh + obj.PeakMWh;
        GenMarg = DirtyMWh - sum(obj.NPGen(CritTax>=TaxCutoff));    % gen from marginal unit
        EmitMarg = GenMarg * obj.NPER(Ind);                         % emissions from marginal unit
        CostMarg = GenMarg * OOC(Ind);                              % cost from marginal unit
        TotEmit = sum(obj.NPEmit(CritTax>=TaxCutoff)) + EmitMarg + obj.PeakEmit;
        TotCost = sum(FossilCosts(CritTax>=TaxCutoff)) + CostMarg + TotCostPeak;
    end

    % Total cost imposed
    CleanMWh = obj.TotMWhAll - TotGen;
    CleanCost = CleanMWh * (obj.ZEcost + ZEcostmarg) / 2;   % cost of clean gen
    CostImposed = CleanCost - (TotCostAll - TotCost);       % change in private cost

    % Total tax
    TotTax = TotEmit * TaxCutoff2;
    TotTaxNoPeak = (TotEmit - obj.PeakEmit) * TaxCutoff2;

    % Electricity price
    ElecPrice = ZEcostmarg;
end



%% Simulate emissions, private costs, tax collection, and tax rate over CT transition
function [EmitPath, GenPath, CostPath, TotTaxPath, TotTaxNoPeakPath, TaxRatePath,...
        ElecPricePath, SBPath] = SimCT(obj)
    % Outputs:
    % EmitPath: total CO2 emissions from remaining fossil (incl peakers) by year
    % GenPath: total generation from remaining fossil (incl peakers) by year
    % CostPath: private cost of CT, by year
    % TotTaxPath: total tax collections, by year
    % TotTaxNoPeakPath: total tax collections from non-peakers, by year
    % TaxRatePath: carbon tax rate, by year
    % ElecPricePath: wholesale price per MWh under CT, by year
    % SBPath: Social benefits of CT, by year

    % initialize output
    EmitPath = zeros(obj.NT,1); GenPath = zeros(obj.NT,1); CostPath = zeros(obj.NT,1);
    TotTaxPath = zeros(obj.NT,1); TotTaxNoPeakPath = zeros(obj.NT,1); 
    TaxRatePath = zeros(obj.NT,1); ElecPricePath = zeros(obj.NT,1); SBPath = zeros(obj.NT,1);
    for s = 0:obj.NT-1
        t = s + 1;      % years since baseline
        [EmitPath(t), GenPath(t), CostPath(t), TotTaxPath(t), TotTaxNoPeakPath(t),...
            TaxRatePath(t), ElecPricePath(t)] = Taxcalc(obj,obj.DirtyMWhYr(t),s);
        SBPath(t) = (obj.TotEmitAll - EmitPath(t)) * obj.SCC - CostPath(t);
    end
end



%% Report out main simulation results
function [EmitPathCES, GenPathCES, CostPathCES, SBPathCES,...
        EmitPathCT, GenPathCT, CostPathCT, TotTaxPathCT, TotTaxNoPeakPathCT, TaxRatePathCT,...
        SBPathCT, ElecPricePathCES, ElecPricePathZES, ElecPricePathCT,...
        TotEmitCES, TotEmitCESNoPeak, TotEmitCT, TotEmitCTNoPeak, DiffTotEmit, PctEmissionsIncreaseCES,...
        TotCostCES, TotCostCT, DiffTotCost, PctCostIncreaseCT, TotTaxCT, TotTaxNoPeakCT,...
        TotSBCES, TotSBCT] = AllResults(obj)
    % Outputs:
    % EmitPath: total CO2 emissions from remaining fossil (incl peakers) by year
    % GenPath: total generation from remaining fossil (incl peakers) by year
    % CostPath: private cost of policy, by year
    % SBPath: social benefits of policy, by year
    % TotTaxPath: total tax collections, by year
    % TotTaxNoPeakPath: total tax collections from non-peakers, by year
    % TaxRatePath: carbon tax rate, by year
    % ElecPrice: wholesale price per MWh, by year
    % TotEmit: total emissions, summed over all years
    % TotEmitNoPeak: total emissions ignoring peakers, summed over all years
    % DiffTotEmit: total emissions from CES minus CT
    % PctEmissionsIncreaseCES: % increase in emissions under CES vs CT
    % TotCost: total private costs imposed by policy, summed over all years
    % DiffTotCost: total private costs imposed by CT minus CES
    % PctCostIncreaseCT: % increase in private costs imposed under CT vs CES
    % TotTaxCT: total carbon taxes, summed over all years
    % TotTaxNoPeakCT: total carbon taxes ignoring peakers, summed over all years
    % TotSB: total social benefits from policy, summed over all years

    % Instantiate model and simulate outcomes under CES and CT
    [EmitPathCES, GenPathCES, CostPathCES, ElecPricePathCES, ElecPricePathZES, SBPathCES] = SimCES(obj);
    [EmitPathCT, GenPathCT, CostPathCT, TotTaxPathCT, TotTaxNoPeakPathCT,...
        TaxRatePathCT, ElecPricePathCT, SBPathCT] = SimCT(obj);

    % Compute total emissions (with and without peakers included)
    TotEmitCES = sum(EmitPathCES);
    TotEmitCESNoPeak = TotEmitCES - obj.PeakMWh * obj.NT;
    TotEmitCT = sum(EmitPathCT);
    TotEmitCTNoPeak = TotEmitCT - obj.PeakMWh * obj.NT;
    DiffTotEmit = TotEmitCES - TotEmitCT;
    PctEmissionsIncreaseCES = DiffTotEmit / TotEmitCT * 100;

    % Compute total private cost imposed
    TotCostCES = sum(CostPathCES);
    TotCostCT = sum(CostPathCT);
    DiffTotCost = TotCostCT - TotCostCES;
    PctCostIncreaseCT = DiffTotCost / TotCostCES * 100;

    % Total taxes collected
    TotTaxCT = sum(TotTaxPathCT);
    TotTaxNoPeakCT = sum(TotTaxNoPeakPathCT);

    % Total social benefits
    TotSBCES = sum(SBPathCES); TotSBCT = sum(SBPathCT);
end



%% Plot emissions paths under CT and CES
function FossilShareDecrease = plotemissions(obj,dirs,EmitPathCT,EmitPathCES)
    % Outputs:
    % FossilShareDecrease: % decrease in fossil MWh (not incl peakers) 

    % Inputs:
    % dirs: directory struct
    % EmitPathCT: total CO2 emissions from remaining fossil (incl peakers) by year, under CT
    % EmitPathCES: total CO2 emissions from remaining fossil (incl peakers) by year, under CES

    FossilGenShare = obj.DirtyMWhYr / max(obj.DirtyMWhYr) * 100;
    FossilShareDecrease = 100 - FossilGenShare;
    EmitShareCES = (EmitPathCES-obj.PeakEmit) / (max(EmitPathCES)-obj.PeakEmit) * 100;
    EmitShareCT = (EmitPathCT-obj.PeakEmit) / (max(EmitPathCT)-obj.PeakEmit) * 100;

    % Flag for model type
    if strcmp(class(obj),'GenModel_GasCoal')==1
        gcflag = 1;         % flag for coal-gas shift model
    else
        gcflag = 0;
    end
    
    % Plot
    clear h
    plot(FossilShareDecrease,EmitShareCT,'-k','LineWidth',3); hold on   % carbon tax
    plot(FossilShareDecrease,EmitShareCES,'-.r','LineWidth',3);         % CES
    grid; xlabel('Percent decrease in fossil MWh generated');
    ylabel('CO2 emissions as % of baseline emissions');
    legend('Carbon tax','Clean energy standard','Location','northeast');
    axis([0 100 0 100]);
    hold off
    h = gcf;
    set(gca,'FontSize',25);
    set(h,'PaperOrientation','landscape');
    set(h,'PaperUnits','normalized');
    set(h,'PaperPosition', [0 0 1 1]);
    % Save plot
    filestr = sprintf('/figures_slides/CTvsCESemissions_%1.0f_%1.2fgas.pdf',[gcflag; obj.Pgas0]);
    outfile = strcat(dirs.pdir, filestr);
    print(h,outfile,'-dpdf');

    % Plot formatted for paper
    set(gca,'FontName','Times New Roman');
    set(gca,'FontSize',30);
    filestr = sprintf('/figures/CTvsCESemissions_%1.0f_%1.2fgas.pdf',[gcflag; obj.Pgas0]);
    outfile = strcat(dirs.pdir, filestr);
    print(h,outfile,'-dpdf');
end



%% Plot social benefit paths under CT and CES
function SBIncreasePct = plotSB(obj,dirs,SBPathCT,SBPathCES)
    % Outputs:
    % SBIncreasePct: % increase in total social benefits from CT vs CES

    % Inputs:
    % dirs: directory struct
    % SBPathCT: social benefits by year, under CT (in $)
    % SBPathCES: social benefits by year, under CES (in $)

    FossilGenShare = obj.DirtyMWhYr / max(obj.DirtyMWhYr) * 100;
    FossilShareDecrease = 100 - FossilGenShare;

    SBIncreasePct = sum(SBPathCT) / sum(SBPathCES) * 100 - 100;
    SBCT = SBPathCT / 1e9;  SBCES = SBPathCES / 1e9;    % convert to billions of $
    
    % Plot
    clear h
    plot(FossilShareDecrease,SBCT,'-k','LineWidth',3); hold on   % carbon tax
    plot(FossilShareDecrease,SBCES,'-.r','LineWidth',3);         % CES
    grid; xlabel('Percent decrease in fossil MWh generated');
    ylabel('Increase in social surplus, $billion/year');
    legend('Carbon tax','Clean energy standard','Location','northwest');
    axis([0 100 0 250]);
    hold off
    h = gcf;
    set(gca,'FontSize',25);
    set(h,'PaperOrientation','landscape');
    set(h,'PaperUnits','normalized');
    set(h,'PaperPosition', [0 0 1 1]);
    % Save plot
    filestr = sprintf('/figures_slides/SocialBenefits_%1.2fgas.pdf',obj.Pgas0);
    outfile = strcat(dirs.pdir, filestr);
    print(h,outfile,'-dpdf');

    % Plot formatted for paper
    set(gca,'FontName','Times New Roman');
    set(gca,'FontSize',30);
    filestr = sprintf('/figures/SocialBenefits_%1.2fgas.pdf',obj.Pgas0);
    outfile = strcat(dirs.pdir, filestr);
    print(h,outfile,'-dpdf');
end



%% Plot carbon tax rate
function dummy = plottaxrate(obj,dirs,FossilShareDecrease,TaxRatePathCT)
    % Outputs:
    % dummy: dummy output. True output is set of plots
    dummy = 0;

    % Inputs:
    % dirs: directory struct
    % FossilShareDecrease: % decrease in fossil MWh (not incl peakers) 
    % TaxRatePathCT: carbon tax rate, by year

    clear h
    plot(FossilShareDecrease,TaxRatePathCT,'-k','LineWidth',3); hold on   % carbon tax
    grid; xlabel('Percent decrease in fossil MWh generated');
    ylabel('Carbon tax rate, $ per tonne CO2');
    axis([0 100 0 350]);
    hold off
    h = gcf;
    set(gca,'FontSize',25);
    set(h,'PaperOrientation','landscape');
    set(h,'PaperUnits','normalized');
    set(h,'PaperPosition', [0 0 1 1]);
    % Save plot
    filestr = sprintf('/figures_slides/CarbonTaxRates_%1.2fgas.pdf',obj.Pgas0);
    outfile = strcat(dirs.pdir, filestr);
    print(h,outfile,'-dpdf');

    % Plot formatted for paper
    set(gca,'FontName','Times New Roman');
    set(gca,'FontSize',30);
    filestr = sprintf('/figures/CarbonTaxRates_%1.2fgas.pdf',obj.Pgas0);
    outfile = strcat(dirs.pdir, filestr);
    print(h,outfile,'-dpdf');
end



%% Plot carbon tax revenue
function dummy = plottaxrev(obj,dirs,FossilShareDecrease,TotTaxNoPeakPathCT)
    % Outputs:
    % dummy: dummy output. True output is set of plots
    dummy = 0;

    % Inputs:
    % dirs: directory struct
    % FossilShareDecrease: % decrease in fossil MWh (not incl peakers) 
    % TotTaxNoPeakPathCT: total tax collections from non-peakers, by year

    clear h
    plot(FossilShareDecrease,TotTaxNoPeakPathCT/1e9,'-k','LineWidth',3); hold on   % carbon tax
    grid; xlabel('Percent decrease in fossil MWh generated');
    ylabel('Carbon tax revenue, $billion');
    axis([0 100 0 50]);
    hold off
    h = gcf;
    set(gca,'FontSize',25);
    set(h,'PaperOrientation','landscape');
    set(h,'PaperUnits','normalized');
    set(h,'PaperPosition', [0 0 1 1]);
    % Save plot
    filestr = sprintf('/figures_slides/CTrevenue_%1.2fgas.pdf',obj.Pgas0);
    outfile = strcat(dirs.pdir, filestr);
    print(h,outfile,'-dpdf');

    % Plot formatted for paper
    set(gca,'FontName','Times New Roman');
    set(gca,'FontSize',30);
    filestr = sprintf('/figures/CTrevenue_%1.2fgas.pdf',obj.Pgas0);
    outfile = strcat(dirs.pdir, filestr);
    print(h,outfile,'-dpdf');
end



%% Plot wholesale electricity prices
function dummy = plotelecprice(obj,dirs,ElecPricePathCT,ElecPricePathCES,ElecPricePathZES)
    % Outputs:
    % dummy: dummy output. True output is set of plots
    dummy = 0;

    % Inputs:
    % dirs: directory struct
    % ElecPricePathCT: wholesale price per MWh, by year, under CT
    % ElecPricePathCES: wholesale price per MWh, by year, under CES
    % ElecPricePathCES: wholesale price per MWh, by year, under ZES

    FossilGenShare = obj.DirtyMWhYr / max(obj.DirtyMWhYr) * 100;
    FossilShareDecrease = 100 - FossilGenShare;

    % Plot all three policies
    clear h
    plot(FossilShareDecrease,ElecPricePathCT,'-k','LineWidth',3); hold on   % carbon tax
    plot(FossilShareDecrease,ElecPricePathCES,'-.r','LineWidth',3);         % CES
    plot(FossilShareDecrease,ElecPricePathZES,'--b','LineWidth',3);         % ZES
    grid; xlabel('Percent decrease in fossil MWh generated');
    ylabel('Wholesale electricity price, $/MWh');
    legend('Carbon tax','Clean energy standard','Zero emission subsidy','Location','northwest');
    axis([0 100 0 obj.ZEcostMax+10]);
    hold off
    h = gcf;
    set(gca,'FontSize',25);
    set(h,'PaperOrientation','landscape');
    set(h,'PaperUnits','normalized');
    set(h,'PaperPosition', [0 0 1 1]);
    % Save plot
    filestr = sprintf('/figures_slides/CTvsCESvsZESelecprices_%1.2fgas.pdf',obj.Pgas0);
    outfile = strcat(dirs.pdir, filestr);
    print(h,outfile,'-dpdf');
    % Plot formatted for paper
    set(gca,'FontName','Times New Roman');
    set(gca,'FontSize',30);
    filestr = sprintf('/figures/CTvsCESvsZESelecprices_%1.2fgas.pdf',obj.Pgas0);
    outfile = strcat(dirs.pdir, filestr);
    print(h,outfile,'-dpdf');

    % Plot with just CT and CES
    clear h
    plot(FossilShareDecrease,ElecPricePathCT,'-k','LineWidth',3); hold on   % carbon tax
    plot(FossilShareDecrease,ElecPricePathCES,'-.r','LineWidth',3);         % CES
    grid; xlabel('Percent decrease in fossil MWh generated');
    ylabel('Wholesale electricity price, $/MWh');
    legend('Carbon tax','Clean energy standard','Location','northwest');
    axis([0 100 0 obj.ZEcostMax+10]);
    hold off
    h = gcf;
    set(gca,'FontSize',25);
    set(h,'PaperOrientation','landscape');
    set(h,'PaperUnits','normalized');
    set(h,'PaperPosition', [0 0 1 1]);
    % Save plot
    filestr = sprintf('/figures_slides/CTvsCESelecprices_%1.2fgas.pdf',obj.Pgas0);
    outfile = strcat(dirs.pdir, filestr);
    print(h,outfile,'-dpdf');

    % Plot with just CT
    clear h
    plot(FossilShareDecrease,ElecPricePathCT,'-k','LineWidth',3); hold on   % carbon tax
    grid; xlabel('Percent decrease in fossil MWh generated');
    ylabel('Wholesale electricity price, $/MWh');
    axis([0 100 0 obj.ZEcostMax+10]);
    hold off
    h = gcf;
    set(gca,'FontSize',25);
    set(h,'PaperOrientation','landscape');
    set(h,'PaperUnits','normalized');
    set(h,'PaperPosition', [0 0 1 1]);
    % Save plot
    filestr = sprintf('/figures_slides/CTelecprices_%1.2fgas.pdf',obj.Pgas0);
    outfile = strcat(dirs.pdir, filestr);
    print(h,outfile,'-dpdf');
end



%% Compute weighted covariance
function WCov = weightedcov(obj,X1,X2,W)
    % Outputs:
    % WCov: weighted covariance (scalar)

    % Inputs:
    % X1, X2: column vectors of identical length
    % W: column vector of weights (same length)

    Wsum = sum(W);
    WCov = W' * ((X1 - X1'*W/Wsum) .* (X2 - X2'*W/Wsum)) / Wsum;
end



%% Bubble plot ongoing op costs vs emissions rate
function [CorrAll, Corr100, CorrNonPeak] = bubbleOCCER(obj,dirs,noplot)
    % Outputs:
    % CorrAll: MWh weighted correlation between OOC and emissions rate
    % Coor100: MWh weighted correlation betwwen OOC and emissions rate, conditional on OOC<=100
    % CorrNonPeak: MWh weighted correlation betwwen OOC and emissions rate, non-peakers only
    
    % Inputs:
    % dirs: directory struct
    % noplot: 0/1 flag for not doing the plots

    % Obtain ongoing op costs at baseline
    OOC = CalcOOC(obj,0);
    
    % Create separate X, Y, and size vectors for each technology
    Xcoal = OOC(obj.dataTech=="Coal"); Ycoal = obj.dataER(obj.dataTech=="Coal");
    SZcoal = obj.dataGen(obj.dataTech=="Coal");
    Xngcc = OOC(obj.dataTech=="NGCC"); Yngcc = obj.dataER(obj.dataTech=="NGCC");
    SZngcc = obj.dataGen(obj.dataTech=="NGCC");
    Xogas = OOC(obj.dataTech=="NGCT" | obj.dataTech=="NGST");
    Yogas = obj.dataER(obj.dataTech=="NGCT" | obj.dataTech=="NGST");
    SZogas = obj.dataGen(obj.dataTech=="NGCT" | obj.dataTech=="NGST");
    Xoil = OOC(obj.dataTech=="Oil"); Yoil = obj.dataER(obj.dataTech=="Oil");
    SZoil = obj.dataGen(obj.dataTech=="Oil");

    % Flag for model type
    if strcmp(class(obj),'GenModel_GasCoal')==1
        gcflag = 1;         % flag for coal-gas shift model
    else
        gcflag = 0;
    end

    % Default to making the plots if the noplot argument is missing
    if nargin==2
        noplot = 0;
    else
    end

    % Create plot censored at $100/MWh. No oil.
    if noplot==0
        clear h
        bubblechart(Xcoal,Ycoal,SZcoal,'MarkerFaceAlpha',0.01,...
            'MarkerFaceColor','black','MarkerEdgeColor','black'); hold on
        bubblechart(Xngcc,Yngcc,SZngcc,'MarkerFaceAlpha',0.01,...
            'MarkerFaceColor','red','MarkerEdgeColor','blue');
        bubblechart(Xogas,Yogas,SZogas,'MarkerFaceAlpha',0.01,...
            'MarkerFaceColor','red','MarkerEdgeColor','red');
        axis([15 100 0 2.5]);
        legend('Coal','Natural gas combined cycle','Other natural gas','Location','northeast');
        grid; xlabel('Ongoing operating cost, $/MWh');
        ylabel('Emissions rate, tonnes CO2 per MWh');
        hold off
        h = gcf;
        set(gca,'FontSize',25);
        set(h,'PaperOrientation','landscape');
        set(h,'PaperUnits','normalized');
        set(h,'PaperPosition', [0 0 1 1]);
        % Save plot
        filestr = sprintf('/figures_slides/GenBubble_%1.0f_%1.2fgas.pdf',[gcflag; obj.Pgas0]);
        outfile = strcat(dirs.pdir, filestr);
        print(h,outfile,'-dpdf');
    
        % Plot formatted for paper
        set(gca,'FontName','Times New Roman');
        set(gca,'FontSize',30);
        filestr = sprintf('/figures/GenBubble_%1.0f_%1.2fgas.pdf',[gcflag; obj.Pgas0]);
        outfile = strcat(dirs.pdir, filestr);
        print(h,outfile,'-dpdf');
    else
    end

    % Get MWh weighted correlation between OOC and emissions rate
    X1 = OOC; X2 = obj.dataER; W = obj.dataGen;
    CorrAll = weightedcov(obj,X1,X2,W) /...
        sqrt(weightedcov(obj,X1,X1,W) * weightedcov(obj,X2,X2,W));

    % Get MWh weighted correlation between OOC and emissions rate for OOC<=100
    N100 = OOC<=100;
    X1 = OOC(N100); X2 = obj.dataER(N100); W = obj.dataGen(N100);
    Corr100 = weightedcov(obj,X1,X2,W) /...
        sqrt(weightedcov(obj,X1,X1,W) * weightedcov(obj,X2,X2,W));

    % Get MWh weighted correlation between OOC and emissions rate for non-peakers only
    X1 = OOC(~obj.Peaker); X2 = obj.dataER(~obj.Peaker); W = obj.dataGen(~obj.Peaker);
    CorrNonPeak = weightedcov(obj,X1,X2,W) /...
        sqrt(weightedcov(obj,X1,X1,W) * weightedcov(obj,X2,X2,W));
end


end
end






























