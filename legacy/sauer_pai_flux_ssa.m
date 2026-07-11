function result = sauer_pai_flux_ssa(case_data, options)
%SAUER_PAI_FLUX_SSA Generic sixth-order flux-state multimachine SSSA.
%   CASE_DATA supplies the network, operating point, machine parameters,
%   load model, and saturation curve. Published eigenvalues are never read
%   by this model-building path.

if nargin < 1 || isempty(case_data)
    error('sauer_pai_flux_ssa:caseRequired', 'case_data is required.');
end
if nargin < 2 || isempty(options)
    options = struct();
end
result = stability.synchronous_flux_ssa(case_data, options);
result.metadata.benchmark = char(case_data.system_name);
result.metadata.model = 'sixth-order flux-state';
result.metadata.power_flow = 'pfsolver.powerflow_fsolve';
end
