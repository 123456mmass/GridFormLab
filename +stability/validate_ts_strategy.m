function strategy = validate_ts_strategy(strategy)
%VALIDATE_TS_STRATEGY  Internal step-layer strategy validator (R2).
%   Validates the required fields, function arity, and dimensions of a TS
%   step strategy struct. This is the INTERNAL step-layer validator; the
%   top-level bundle validator is validate_ts_bundle. A TS strategy does NOT
%   double as an SSSA model (separate capability, separate validator).
%
%   Required fields:
%     .model            - string (model name, for diagnostics)
%     .dae_f            - function handle @(x,y) or @(x,y,Y)  (legacy path)
%     .dae_g            - function handle @(x,y,Y) or [] for linear models
%     .jac_y            - function handle @(x,y,Y) or [] for linear models
%     .needs_jyy        - logical
%     .needs_algebraic_solve - logical
%     .electrical_power - function handle
%     .state_split      - struct with .ng, .delta_idx, .omega_idx
%     .reconstruct      - function handle @(x,y,Y)
%
%   Optional (R1 provider path):
%     .provider         - provider struct (absent/empty = legacy path)
%     .dae_f_u          - @(x,y,Y,u) (required if provider present, linear)
%                          or @(x,y,u) (nonlinear, 3-arg) — see validate_ts_bundle
%     .dae_g_u, .jac_y_u, .reconstruct_u - provider-aware closures
%
%   Source: project R2 design (docs/project/plans/ibr_interface_foundation.md).

required = {'model','dae_f','dae_g','jac_y','needs_jyy', ...
    'needs_algebraic_solve','electrical_power','state_split','reconstruct'};
for k = 1:numel(required)
    if ~isfield(strategy, required{k})
        error('validate_ts_strategy:missingField', ...
            'TS strategy missing required field "%s".', required{k});
    end
end
% Function-handle checks.
fh_fields = {'dae_f','electrical_power','reconstruct'};
for k = 1:numel(fh_fields)
    if ~isa(strategy.(fh_fields{k}),'function_handle')
        error('validate_ts_strategy:badHandle', ...
            'Field "%s" must be a function handle.', fh_fields{k});
    end
end
if ~islogical(strategy.needs_jyy) || ~islogical(strategy.needs_algebraic_solve)
    error('validate_ts_strategy:badLogical', ...
        'needs_jyy and needs_algebraic_solve must be logical.');
end
% Linear models (needs_algebraic_solve=false) must have dae_g=[] and jac_y=[].
if ~strategy.needs_algebraic_solve
    if ~isempty(strategy.dae_g) || ~isempty(strategy.jac_y)
        error('validate_ts_strategy:linearMismatch', ...
            'Linear model (needs_algebraic_solve=false) must have dae_g=[] and jac_y=[].');
    end
else
    if ~isa(strategy.dae_g,'function_handle') || ~isa(strategy.jac_y,'function_handle')
        error('validate_ts_strategy:nonlinearHandle', ...
            'Nonlinear model must have dae_g and jac_y as function handles.');
    end
end
% state_split checks.
ss = strategy.state_split;
if ~isfield(ss,'ng') || ~isfield(ss,'delta_idx') || ~isfield(ss,'omega_idx')
    error('validate_ts_strategy:badStateSplit', ...
        'state_split must have ng, delta_idx, omega_idx.');
end
if ~isscalar(ss.ng) || ss.ng < 1
    error('validate_ts_strategy:badNg', 'state_split.ng must be a positive scalar.');
end
% Optional provider: if present, require provider-aware closures.
if isfield(strategy,'provider') && ~isempty(strategy.provider)
    pu_fields = {'dae_f_u','dae_g_u','jac_y_u'};
    for k = 1:numel(pu_fields)
        if ~isfield(strategy, pu_fields{k})
            error('validate_ts_strategy:missingProviderField', ...
                'Provider present but "%s" missing.', pu_fields{k});
        end
    end
end
strategy = strategy;   % pass-through (value struct)
end
