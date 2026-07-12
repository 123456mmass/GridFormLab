function strategy = ts_model_strategy(model, dae, varargin)
%TS_MODEL_STRATEGY  Build a model-strategy struct for the shared TS step kernel.
%   STRATEGY = ts_model_strategy(MODEL, DAE) wraps a model's differential RHS,
%   algebraic solve, Jacobian, and output reconstruction behind a single
%   contract so the shared trapezoidal kernel (ts_step_kernel) and the adaptive
%   controller (ts_adaptive_driver) can call any model without duplicating
%   integration logic.
%
%   This is the COMMON STEP CONTRACT layer. The kernel stays the single
%   production trapezoidal implementation; each model supplies only its own
%   algebraic solver via this strategy.
%
%   MODEL is one of:
%     'padiyar'    — nonlinear DAE algebraic Newton (padiyar_model11_dae).
%     'emf6'       — nonlinear DAE algebraic Newton (emf6_dae).
%     'classical'  — direct linear network solve V = Y\Iinj (Phase 2).
%
%   For 'padiyar'/'emf6', the strategy wraps the EXACT closures already used by
%   ts_simulate_padiyar_model11 / ts_simulate_emf6, so routing those drivers
%   through the strategy path is bit-identical to the legacy signature path
%   (verified by tests/test_ts_strategy_equivalence.m).
%
%   Strategy fields:
%     .model            — model name string
%     .dae_f            — @(x,y) differential RHS (matches legacy dae_f signature)
%     .dae_g            — @(x,y,Y) algebraic residual ([] for classical)
%     .jac_y            — @(x,y,Y) dg/dy ([] for classical; FD for nonlinear)
%     .needs_jyy        — false for classical (linear); true for nonlinear DAE
%     .electrical_power — @(x,y) Pe (per generator)
%     .reconstruct      — @(x,y) struct for output recording
%     .state_split      — struct with indices for delta/omega for LTE scaling

opt = struct();
if nargin >= 3 && ~isempty(varargin{1}), opt = varargin{1}; end

switch lower(model)
case 'padiyar'
    strategy = padiyar_strategy(dae, opt);
case 'emf6'
    strategy = emf6_strategy(dae, opt);
case 'classical'
    strategy = classical_strategy(dae, opt);
otherwise
    error('ts_model_strategy:badModel','Unknown model "%s".', model);
end
end

% =========================================================================
function s = padiyar_strategy(dae, ~)
% Wrap the exact closures from ts_simulate_padiyar_model11 so routing through
% the strategy is bit-identical to the legacy (dae_f,dae_g,Y,Jyy,opt) path.
ns = dae.ns; ng = dae.ng;
s.model = 'padiyar';
s.dae_f = @(x,y) dae.dae_f(x,y);
s.dae_g = @(x,y,Y) dae.dae_g(x,y,Y);
s.jac_y = @(x,y,Y) stability.ts_jac_y_fd(x,y,Y,dae.dae_g);
s.needs_jyy = true;
s.electrical_power = @(x,y) dae.electrical_power(x,y);
s.state_split = struct('ng',ng,'ns',ns, ...
    'delta_idx',1:ns:(ns*ng), 'omega_idx',2:ns:(ns*ng));
s.reconstruct = @(x,y) padiyar_reconstruct(x,y,dae);
end

function s = emf6_strategy(dae, ~)
% Wrap the exact closures from ts_simulate_emf6 so routing through the strategy
% is bit-identical to the legacy path.
ng = dae.ng; ns = 6;
s.model = 'emf6';
s.dae_f = @(x,y) dae.dae_f(x,y);
s.dae_g = @(x,y,Y) dae.dae_g(x,y,Y);
s.jac_y = @(x,y,Y) stability.ts_jac_y_fd(x,y,Y,dae.dae_g);
s.needs_jyy = true;
s.electrical_power = @(x,y) dae.electrical_power(x,y);
s.state_split = struct('ng',ng,'ns',ns, ...
    'delta_idx',1:ns:(ns*ng), 'omega_idx',2:ns:(ns*ng));
s.reconstruct = @(x,y) emf6_reconstruct(x,y,dae);
end

function s = classical_strategy(~, ~)
% Classical strategy is implemented in Phase 2 (classical_dae wrapper +
% solve_network extraction). Phase 1 only wires the nonlinear DAE models.
error('ts_model_strategy:classicalNotReady', ...
    'Classical strategy is Phase 2 work (classical_dae wrapper). Not yet available.');
end

function out = padiyar_reconstruct(x,y,dae)
ns = dae.ns; ng = dae.ng;
out.delta = x(1:ns:ns*ng).';
out.omega = x(2:ns:ns*ng).';
out.Eqp = x(3:ns:ns*ng).';
out.Edp = x(4:ns:ns*ng).';
if ns >= 5, out.Efd = x(5:ns:ns*ng).'; end
out.Pe = dae.electrical_power(x,y).';
out.Vbus = abs(complex(y(1:2:end),y(2:2:end))).';
end

function out = emf6_reconstruct(x,y,dae)
ns = 6; ng = dae.ng;
out.delta = x(1:ns:ns*ng).';
out.omega = x(2:ns:ns*ng).';
out.Pe = dae.electrical_power(x,y).';
out.Vbus = abs(complex(y(1:2:end),y(2:2:end))).';
end
