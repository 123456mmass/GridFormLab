function is_pf = is_powerflow_case_loader(loader)
%DEPRECATED (Phase C): superseded by the Studio GUI (+studio/launch.m).
%   Header banner only; behavior unchanged.
try
    case_data = loader();
    is_pf = isstruct(case_data) && isfield(case_data, 'bus_data') && isfield(case_data, 'line_data');
catch
    is_pf = false;
end
end
