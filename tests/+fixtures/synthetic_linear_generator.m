function bundle = synthetic_linear_generator(case_data, opt)
%SYNTHETIC_LINEAR_GENERATOR  Test-only 2-state linear generator bundle (R2/R3).
%   Returns a model BUNDLE (bundle.ts + bundle.sssa.model) for a synthetic
%   2-state classical-style generator (delta, omega) on a 1-generator network.
%   This is a TEST-ONLY fixture (lives in tests/+fixtures, called as
%   fixtures.synthetic_linear_generator). It is NOT in +stability or
%   production +cases, and has NO reference to +ibr.
%
%   The fixture wraps the project classical_dae for a 1-generator case so the
%   bundle's ts_strategy is a real classical strategy (bit-identical to the
%   legacy path when no provider is present). The sssa_model is a minimal
%   linearized model for SSSA dispatch testing.
%
%   Source: project classical_dae (synthetic wrapper, no +ibr).

if nargin < 1 || isempty(case_data)
    case_data = cases.case_matpower6_case14();
end
if nargin < 2 || isempty(opt), opt = struct(); end
% Build the classical DAE for the case (1 equivalent generator per bus).
cdae = stability.classical_dae(case_data, opt);
strat = stability.ts_model_strategy('classical', cdae);
% Bundle.ts: complete TS initialization.
ts.strategy = strat;
ts.x0 = cdae.x0;
ts.y0 = cdae.y0;
% Topology: Ypre = Ynet; Yfault/Ypost built from fault_bus + Zf.
Ypre = cdae.Ynet;
Yfault = Ypre; Ypost = Ypre;
if isfield(opt,'fault_bus') && ~isempty(opt.fault_bus) && isfield(opt,'Zf') && ~isempty(opt.Zf)
    fb = find(cdae.bus_ids == opt.fault_bus, 1);
    if ~isempty(fb)
        Yfault(fb,fb) = Yfault(fb,fb) + 1/opt.Zf;
    end
end
ts.topology = struct('Ypre',Ypre,'Yfault',Yfault,'Ypost',Ypost);
ts.mapping = struct('bus_ids',cdae.bus_ids,'gen_buses',cdae.gen_buses);
ts.metadata = struct('device_id','synthetic_linear_generator', ...
    'device_type','classical_2state','provenance','tests/+fixtures');
% Bundle.sssa.model: minimal SSSA model (linearized swing). For the R2
% dispatch test we only need a valid model struct that multimachine_ssa can
% consume; the eigenvalues are not gated here.
sssa.model = struct('x0',cdae.x0,'y0',cdae.y0, ...
    'f',strat.dae_f,'g',@(x,y) zeros(numel(cdae.y0),1), ...
    'state_names',{{'delta','omega'}});
bundle.ts = ts;
bundle.sssa = sssa;
bundle.metadata = struct('dispatch','explicit_model_fn');
end
