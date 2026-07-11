function dae = genpj6_dae(case_data, varargin)
%GENPJ6_DAE Build the 6th-order GENTPJ DAE for a case.
%   DAE = genpj6_dae(CASE) returns a struct with the nonlinear DAE function
%   handles and operating point needed by ts_simulate_genpj6.
%
%   This wraps the validated Kundur 6th-order model
%   (stability.kundur_ex126_kundur_ssa, <0.5% eigenvalue error vs Kundur
%   Table E12.3) so the general TS engine can run 6th-order Kundur through
%   the same entry point as classical cases.
%
%   Fields returned: dae_f, dae_g, init, Ynet, M, base, nb, ng, bus_ids,
%   zb_scale, load_model.

load_model = 'cc_p_cz_q';
if nargin > 1 && isstruct(varargin{1})
    if isfield(varargin{1},'load_model') && ~isempty(varargin{1}.load_model)
        load_model = varargin{1}.load_model;
    end
end

% Dispatch on case format. Only Kundur provides a validated 6th-order DAE
% so far; other formats raise a clear error (extend here as new 6th-order
% cases are added).
if isfield(case_data,'bus_data') && isfield(case_data,'machines') && ...
        isfield(case_data.machines,'reactances')
    ssa = stability.kundur_ex126_kundur_ssa('options', struct('load_model',load_model));
    if isempty(ssa.dae_f), error('genpj6_dae:noDAE','SSSA did not expose DAE handles.'); end
    dae.dae_f = ssa.dae_f;
    dae.dae_g = ssa.dae_g;
    dae.init  = ssa.init;
    dae.Ynet  = ssa.Ynet;
    dae.M     = case_data.machines;
    dae.base  = case_data.base_values;
    dae.nb    = size(ssa.Ynet,1);
    dae.ng    = ssa.init.ng;
    dae.bus_ids = (1:dae.nb)';
    dae.zb_scale = ssa.init.zb_scale;
    dae.load_model = load_model;
    dae.case_name = case_data.system_name;
else
    error('genpj6_dae:unsupportedCase', ...
        ['6th-order DAE is not yet available for this case format. ' ...
         'Only Kundur-style cases (bus_data + machines.reactances) are supported. ' ...
         'Add a DAE builder here to extend.']);
end
end
