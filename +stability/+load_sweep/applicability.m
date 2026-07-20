function [applicable, reason, route] = applicability(case_data)
%APPLICABILITY  Case-applicability predicate for SSSA load sweep.
%   [APPLICABLE, REASON, ROUTE] = stability.load_sweep.applicability(CASE_DATA)
%   returns whether the SSSA load sweep is applicable to CASE_DATA and the
%   route to use.
%
%   - Ideal SMIB verification cases (smib_verification/1.0 schema, no
%     load-demand field): APPLICABLE=false,
%     REASON='LOAD_SWEEP_NOT_APPLICABLE_TO_IDEAL_SMIB', ROUTE='none'.
%   - power_case/1.0 network cases with nonzero load: APPLICABLE=true,
%     REASON='', ROUTE='sg' or 'ieee14_ibr' (resolved by the caller based on
%     scenario/IBR configuration, not here).
%
%   This is a centralized predicate (not endsWith(case_id,'_smib')) so a future
%   load-bearing fixture is not incorrectly rejected.

if ~isstruct(case_data)
    applicable = false;
    reason = 'LOAD_SWEEP_NOT_APPLICABLE_NON_STRUCT_CASE';
    route = 'none';
    return;
end

% Ideal SMIB verification cases have no load-demand field.
if isfield(case_data,'smib_verification')
    applicable = false;
    reason = 'LOAD_SWEEP_NOT_APPLICABLE_TO_IDEAL_SMIB';
    route = 'none';
    return;
end

% smib_loaded_ibr/1.0: single IBR to infinite bus with shunt load. Applicable;
% route resolved by the caller as 'smib_ibr'.
if isfield(case_data,'smib_loaded_ibr') && isstruct(case_data.smib_loaded_ibr)
    m = case_data.smib_loaded_ibr;
    if isfield(m,'P_load_base_pu') && isfield(m,'Q_load_base_pu') && ...
            ~(m.P_load_base_pu == 0 && m.Q_load_base_pu == 0)
        applicable = true;
        reason = '';
        route = '';
        return;
    end
    applicable = false;
    reason = 'LOAD_SWEEP_NOT_APPLICABLE_ZERO_LOAD';
    route = 'none';
    return;
end

% power_case/1.0 network cases require bus_data with load columns.
if ~isfield(case_data,'bus_data') || ~ismatrix(case_data.bus_data) || ...
        size(case_data.bus_data,2) < 8
    applicable = false;
    reason = 'LOAD_SWEEP_NOT_APPLICABLE_NO_BUS_DATA';
    route = 'none';
    return;
end

% Require at least one nonzero load to sweep.
Pload = case_data.bus_data(:,7);
Qload = case_data.bus_data(:,8);
if all(Pload == 0) && all(Qload == 0)
    applicable = false;
    reason = 'LOAD_SWEEP_NOT_APPLICABLE_ZERO_LOAD';
    route = 'none';
    return;
end

applicable = true;
reason = '';
route = '';   % caller resolves 'sg' vs 'ieee14_ibr' from scenario config
end
