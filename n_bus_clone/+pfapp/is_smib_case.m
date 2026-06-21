function tf = is_smib_case(case_data)
%IS_SMIB_CASE True if a case struct is a Kundur SMIB stability case.
%   SMIB cases carry a .model field ('A'/'B'/'C'/'D') and machine/network
%   structs but no bus_data/line_data, so they cannot be solved by the
%   steady-state power-flow / CPF / OPF methods.

tf = false;
if ~isstruct(case_data)
    return;
end
if isfield(case_data, 'model') && ischar(case_data.model) && any(strcmpi(case_data.model, {'A','B','C','D'}))
    tf = true;
end
end
