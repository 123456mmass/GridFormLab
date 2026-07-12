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
    if isstruct(model)
        % R2: prebuilt strategy struct (validated upstream by validate_ts_strategy).
        % Bypass factory construction but NOT schema validation.
        strategy = model;
    else
        error('ts_model_strategy:badModel','Unknown model "%s".', model);
    end
end
% R1: optional input provider (default absent = exact legacy behavior).
% When absent, the kernel calls the original dae_f/dae_g closures with NO u
% argument (FP-identical to the pre-R1 path). When present, the kernel uses
% the separate provider-aware path (strategy.dae_f_u / dae_g_u).
if ~isfield(strategy,'provider')
    strategy.provider = [];   % absent => legacy path
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
s.needs_algebraic_solve = true;
s.electrical_power = @(x,y) dae.electrical_power(x,y);
s.state_split = struct('ng',ng,'ns',ns, ...
    'delta_idx',1:ns:(ns*ng), 'omega_idx',2:ns:(ns*ng));
s.reconstruct = @(x,y,~) padiyar_reconstruct(x,y,dae);
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
s.needs_algebraic_solve = true;
s.electrical_power = @(x,y) dae.electrical_power(x,y);
s.state_split = struct('ng',ng,'ns',ns, ...
    'delta_idx',1:ns:(ns*ng), 'omega_idx',2:ns:(ns*ng));
s.reconstruct = @(x,y,~) emf6_reconstruct(x,y,dae);
end

function s = classical_strategy(dae, ~)
% Classical model: direct linear network solve V = (Y+Ygen)\Iinj. No nonlinear
% g. The algebraic state is solved exactly inside dae_f (via solve_network),
% so needs_algebraic_solve=false and the kernel uses classical_step (which
% skips ts_algebraic_solve). Jyy is [] (the "Jacobian" is -Y, exact and constant
% per topology). needs_jyy=false. dae_g and jac_y are [] (empty, NOT function
% handles) to satisfy validate_ts_strategy's linear-model contract; the kernel
% never calls jac_y/dae_g on the classical path (it returns via classical_step
% at ts_step_kernel.m:49 before reaching the jac_y call at L52).
ng = dae.ng; nb = dae.nb;
s.model = 'classical';
s.dae_f = @(x,y,Y) dae.dae_f(x,y,Y);
s.dae_g = [];
s.jac_y = [];
s.needs_jyy = false;
s.needs_algebraic_solve = false;
s.electrical_power = @(x,y,Y) dae.electrical_power(x,y,Y);
s.state_split = struct('ng',ng,'ns',2, ...
    'delta_idx',1:ng, 'omega_idx',(ng+1):(2*ng));
s.reconstruct = @(x,y,Y) classical_reconstruct(x,y,dae,Y);
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

function out = classical_reconstruct(x,y,dae,Y)
% Classical output reconstruction using the current-topology Y. Vbus comes from
% the linear network solution V = (Y+Ygen)\Iinj at (delta, Y); Pe likewise.
if nargin < 4 || isempty(Y), Y = dae.Ynet; end
ng = dae.ng; nb = dae.nb;
out.delta = x(1:ng).';
out.omega = x(ng+1:2*ng).';
out.Pe = dae.electrical_power(x, y, Y).';
% Classical solve_network_linear is internal to classical_dae; recompute V here
% for Vbus. Since classical has no y-state coupling (V is a function of delta
% and Y only), re-solve the linear network at (delta, Y).
V = classical_solve_v(x, dae, Y);
out.Vbus = abs(V).';
end

function V = classical_solve_v(x, dae, Y)
%CLASSICAL_SOLVE_V  Direct linear network solve V = (Y+Ygen)\Iinj for Vbus.
%   Mirrors classical_dae/solve_network_linear (bit-identical).
Eqmag = dae.Eqmag; gbus = dae.gen_buses; bus_ids = dae.bus_ids; Xdp = dae.Xdp;
delta = x(1:numel(gbus));
nb = size(Y,1); ng = numel(gbus);
Yloc = Y; Iinj = zeros(nb,1);
for k = 1:ng
    b = find(bus_ids == gbus(k), 1);
    yg = 1/(1i*Xdp(k));
    E = Eqmag(k)*exp(1i*delta(k));
    Yloc(b,b) = Yloc(b,b) + yg;
    Iinj(b) = Iinj(b) + E*yg;
end
V = Yloc \ Iinj;
end
