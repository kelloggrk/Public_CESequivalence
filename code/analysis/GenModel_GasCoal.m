% Subclass of GenModel that enables shifting of MWh from coal to gas (or vice versa)
% in response to carbon taxes or fuel price changes
classdef GenModel_GasCoal < GenModel
properties
    % List of all properties attached to the model object
    PropSwitch20
    PropSwitch70
    CoalShareSwitch
end
methods
%% Constructor
function obj = GenModel_GasCoal(dirs,PGasIn,Rfinal)
    % Inputs:
    % dirs: directory struct
    % PGasIn: optional manual input of natural gas price ($/mmBtu)
    % Rfinal: $/MWh for zero-emission power at full decarbonization ($/MWh)

    % Get object defns from superclass
    if nargin==1        % No input for PGasIn
        PGasIn = 0;     % set = 0 so superclass uses default 2019 gas price
        Rfinal = 0;     % set = 0 so superclass uses default LBNL estimate
    elseif nargin==2    % No input for Rfinal
        Rfinal = 0;     % set = 0 so superclass uses default LBNL estimate
    else
    end
    obj = obj@GenModel(dirs,PGasIn,Rfinal);

    % MWh that switch from coal to gas in response to a $20/ton carbon tax
    % From Cullen and Mansur (2017) table 4
    CullenMansurRaw20 = 518;      % units of GWh/day
    CullenMansur20 = CullenMansurRaw20 * 365 * 1000;    % MWh/year
    % And the switch in response to a $70/ton carbon tax
    % From Cullen and Mansur (2017) table 4
    CullenMansurRaw70 = 1072;      % units of GWh/day
    CullenMansur70 = CullenMansurRaw70 * 365 * 1000;    % MWh/year

    % Load average annual coal Mwh during the Cullen-Mansur 2006-2012 sample period
    coalMWh20062012file = strcat(dirs.idir,'/EIAdata/AggregatedHistoricalGen/MWhCoal_2006-2012.csv');
    coalMWh20062012 = readmatrix(coalMWh20062012file,'Range',[1 1]); 

    % Proportion of coal that switches to gas in response to a $20/ton and $70/ton carbon tax
    obj.PropSwitch20 = CullenMansur20 / coalMWh20062012;
    obj.PropSwitch70 = CullenMansur70 / coalMWh20062012;

    % See if gas price is different from baseline. If so, shift generation between coal
    % and gas per Cullen and Mansur
    % First recover baseline gas price
    inputparamsfile = strcat(dirs.rdir,'/Input_Parameters.csv');
    inputparams = readmatrix(inputparamsfile,'Range',[1 2]);
    Pgasorig = inputparams(3);         % gas price in baseline year (all prices $/mmBtu)
    if obj.Pgas0==Pgasorig
        obj.CoalShareSwitch = 0;
    else
        % Need average emissions factors for coal and gas in tonne / mmBtu
        GasFlag = obj.dataTech~="Coal" & obj.dataTech~="Oil";
        meanEFgas = sum(obj.dataEmit(GasFlag)) / sum(obj.dataGen(GasFlag).*obj.dataHR(GasFlag));
        meanEFcoal = sum(obj.dataEmit(obj.dataTech=="Coal"))...
            / sum(obj.dataGen(obj.dataTech=="Coal").*obj.dataHR(obj.dataTech=="Coal"));
        % factor to convert dQ/dtax to dQ/dPgas (per Cullen and Mansur)
        factor = obj.Pcoal0 / (meanEFgas*obj.Pcoal0 - meanEFcoal*Pgasorig);
        % Share of coal that switches to gas (negative number means increase in coal)
        obj.CoalShareSwitch = factor * obj.PropSwitch20 / 20 * (obj.Pgas0 - Pgasorig);
        % Update generation for non-peakers
        NewGen = obj.dataGen;
        NPcoal = obj.dataTech=="Coal" & obj.Peaker==0;  % non-peaker coal
        NewGen(NPcoal) = obj.dataGen(NPcoal) * (1 - obj.CoalShareSwitch);
        GasChg = sum(obj.dataGen) - sum(NewGen);        % change in gas generation
        NPgas = GasFlag & obj.Peaker==0;                % flags for non-peaker gas
        OldGas = sum(obj.dataGen(NPgas));               % total generation from non-peaker gas
        NewGen(NPgas) = obj.dataGen(NPgas) * (OldGas + GasChg) / OldGas;    % shift MWh
        % Error check (with tolerance of 1 MWh) that total generation hasn't changed
        if abs(sum(obj.dataGen) - sum(NewGen))>1
            error('Coal-gas shift failed to hold dirty MWh constant');
        else
        end
        % Replace object generation and emissions with new generation and emissions
        obj.dataGen = NewGen;
        obj.dataEmit = obj.dataGen .* obj.dataER;
    end
end



%% Compute tax cutoff assoicated with a carbon tax policy leaving behind some amount of dirty gen
function SwitchShare = ShareCoalSwitch(obj,taxrate)
    % Inputs:
    % taxrate: carbon tax rate in $/tonne (possibly entering as a vector)

    % Outputs
    % SwitchShare: share of coal generation that switches to gas (vector of same length as taxrate)

    % Compute change in proportion switching caused by a $1 change in the tax rate
    % Kink at $20/ton
    slope1 = obj.PropSwitch20 / 20; slope2 = (obj.PropSwitch70 - obj.PropSwitch20) / 50;
    
    % Compute share switching
    if taxrate<=20
        SwitchShare = slope1 * taxrate;
    else
        SwitchShare = slope1 * 20 + slope2 * (taxrate - 20);
    end
    % Cap at 100%
    SwitchShare = min(SwitchShare,1);
end



%% Compute ongoing op cost for a specific generator, given simulation year and carbon tax rate
function OOC = CalcOOCtax(obj,t,taxrate,row)
    % Inputs:
    % t: index year for simulation (calendar year is obj.BaseYear + t)
    % taxrate: carbon tax rate ($/tonne)
    % row: row of generation unit dataset (including peakers)

    % Outputs:
    % OOC: total private ongoing operating cost (scalar)

    % Get relevant fuel price
    if obj.dataTech(row)=="Coal"
        Price = obj.Pcoal0;
    elseif obj.dataTech(row)=="Oil"
        Price = obj.Poil0;
    else
        Price = obj.Pgas0;
    end

    % Total variable costs, $/MWh
    TVC = Price .* obj.dataHR(row) + obj.dataVarOM(row);

    % Age effects for ongoing capex. Coal units only. $/kW
    if obj.dataTech(row)=="Coal"
        y = obj.BaseYear + t;       % calendar year
        AgeCost = obj.AgeFactor * (y - obj.dataStart(row));
    else
        AgeCost = 0;
    end

    % Adjust generation for non-peaker coal plants
    if obj.dataTech(row)=="Coal" && obj.Peaker(row)==0
        SwitchShare = ShareCoalSwitch(obj,taxrate);     % share of coal gen switching to gas
        NewGen = obj.dataGen(row) * (1 - SwitchShare);
    else
        NewGen = obj.dataGen(row);
    end

    % Compute OOC
    FCperMWh = (obj.dataFixedOM(row) + obj.dataCapex(row) + AgeCost)...
        .* obj.dataCap(row) * 1000 ./ NewGen;
    OOC = TVC + FCperMWh;
end



%% Given a carbon tax, compute the difference between the cost of zero-emissions generation
% and the tax-inclusive operating cost of a given unit
function Diff = CostDiffTax(obj,t,taxrate,row)
    % Inputs:
    % t: index year for simulation (calendar year is obj.BaseYear + t)
    % taxrate: carbon tax rate ($/tonne)
    % row: row of generation unit dataset (including peakers)

    % Outputs:
    % Diff: zero-emission cost minus tax-inclusive ongoing operating cost (scalar)

    % Compute OOC, accounting for the carbon tax
    OOC = CalcOOCtax(obj,t,taxrate,row);

    % Marginal cost of zero emissions energy
    ZEcostmarg = obj.ZEcostYr(t+1);

    Diff = ZEcostmarg - (OOC + taxrate * obj.dataER(row));
end



%% Compute tax cutoff assoicated with a carbon tax policy leaving behind some amount of dirty gen
function [TaxCutoff, TaxCutoff2, OOC, OOCall, CritTax] = CalcCostCutoffCT(obj,DirtyMWh,t)
    % Inputs:
    % DirtyMWh: total MWh of fossil still producing after imposition of CT (not including peakers)
    % t: index year for simulation (calendar year is obj.BaseYear + t)

    % Outputs:
    % TaxCutoff: critical tax rate for last fossil plant that runs 100%
    % TaxCutoff2: critical tax rate for fossil plant right on the margin
    % OOC: ongoing operating cost for each non-peaker plant in year t (ignoring
        % coal-gas shift)
    % OOCall: ongoing operating cost for all plants (incl peaker) in year t (ignoring
        % coal-gas shift)
    % CritTax: NNP-vector of unit-level critical carbon tax such that 
        % the ongoing cost of each unit is at least obj.ZEcost

    % First get each unit's OOC in year t, not accounting for any shift of MWh away from coal
    OOCall = CalcOOC(obj,t);
    OOC = OOCall(~obj.Peaker);      % non-peakers only

    ZEcostmarg = obj.ZEcostYr(t+1); % Marginal cost of zero emissions energy

    % Loop thorugh each unit and find its critical tax
    CritTax = zeros(obj.NNP,1);     % initialize
    rowNP = 1;
    options = optimset('TolFun',1e-8,'TolX',1e-8);
    for row = 1:obj.N               % Loop over all units
        % For non-peaker coal plants, need to account for how coal-to-gas shift increases OOC
        if obj.dataTech(row)=="Coal" && obj.Peaker(row)==0
            % Need to numerically solve for the unit's critical tax
            % Define implicit function to feed into fzero
            ifun = @(x) CostDiffTax(obj,t,x,row);
            xguess = (ZEcostmarg - OOCall(row)) ./ obj.dataER(row);     % initial guess
            CritTax(rowNP) = fzero(ifun,xguess,options);      % solve for critical tax
            rowNP = rowNP + 1;
        elseif obj.dataTech(row)~="Coal" && obj.Peaker(row)==0
            % simple critical tax calc for non-coal units
            CritTax(rowNP) = (ZEcostmarg - OOCall(row)) ./ obj.dataER(row);
            rowNP = rowNP + 1;
        else                                                % ignore peaker units
        end  
    end
    CritTax(CritTax<0) = 0;         % units with priv costs > ZEcostmarg

    % Find critical tax rate for marginal unit and highest cost inframarginal unit
    % Can use original generation quantity for each unit because the coal-to-gas shift
    % does not affect total fossil generation within the set of in-the-money generators
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

    % Index of marginal unit
    Ind = find(CritTax==TaxCutoff2);

    % Share of coal that switches to gas
    SwitchShare = ShareCoalSwitch(obj,TaxRate);

    % Total of all peaker costs
    TotCostPeak = sum(OOCall(obj.Peaker) .* obj.dataGen(obj.Peaker));
    % Total of all private costs before policy
    TotCostAll0 = sum(OOCall .* obj.dataGen);

    % Compute outcomes under the tax policy
    if DirtyMWh==0
        TotEmit = obj.PeakEmit; TotGen = obj.PeakMWh; TotCost = TotCostPeak;
    elseif DirtyMWh>=obj.TotMWhAll - obj.PeakMWh
        TotEmit = obj.TotEmitAll; TotGen = obj.TotMWhAll; TotCost = TotCostAll0;
    else
        % Update each unit's generation after coal-to-gas shift
        % First flag which units are coal among non-peakers
        Tech = obj.dataTech(~obj.Peaker);           % technology for non-peakers
        CoalFlag = Tech=="Coal";                    % flag for coal plants
        % Decrease generation from in-the-money coal
        NPGenNew = obj.NPGen;                       % initialize new generation vector
        coalchg = CritTax>=TaxRate & CoalFlag==1;   % coal units with generation changes
        NPGenNew(coalchg) = obj.NPGen(coalchg) * (1-SwitchShare);   % reduce generation
        % Increase generation from in-the-money gas
        GenShift = sum(obj.NPGen) - sum(NPGenNew);  % generation shifted to gas
        gaschg = CritTax>=TaxRate & CoalFlag==0;    % gas units with generation changes
        OldGas = sum(obj.NPGen(gaschg));
        NPGenNew(gaschg) = obj.NPGen(gaschg) * (OldGas + GenShift) / OldGas;    % scale up
        % Error check (with tolerance of 1 MWh) that total in-the-money generation hasn't changed
        if abs(sum(obj.NPGen) - sum(NPGenNew))>1
            error('Coal-gas shift failed to hold dirty MWh constant');
        else
        end
        NPEmit = NPGenNew .* obj.NPER; % update unit emissions
        NPCost = obj.NPGen .* OOC;     % private unit costs: use old costs since FC do not actually change
        TotGen = DirtyMWh + obj.PeakMWh;    % total dirty generation
        GenMarg = DirtyMWh - sum(NPGenNew(CritTax>=TaxCutoff));     % gen from marginal unit
        EmitMarg = GenMarg * obj.NPER(Ind);                         % emissions from marginal unit
        CostMarg = GenMarg * OOC(Ind);                              % cost from marginal unit
        TotEmit = sum(NPEmit(CritTax>=TaxCutoff)) + EmitMarg + obj.PeakEmit;
        TotCost = sum(NPCost(CritTax>=TaxCutoff)) + CostMarg + TotCostPeak;
    end

    % Total private cost imposed
    CleanMWh = obj.TotMWhAll - TotGen;
    CleanCost = CleanMWh * (obj.ZEcost + ZEcostmarg) / 2;   % cost of clean gen
    CostImposed = CleanCost - (TotCostAll0 - TotCost);      % change in private cost

    % Total tax
    TotTax = TotEmit * TaxCutoff2;
    TotTaxNoPeak = (TotEmit - obj.PeakEmit) * TaxCutoff2;

    % Electricity price
    ElecPrice = ZEcostmarg;
end



end
end






























