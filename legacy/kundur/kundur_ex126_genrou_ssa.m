function result = kundur_ex126_genrou_ssa(varargin)
%KUNDUR_EX126_GENROU_SSA Small-signal stability of the Kundur 4-machine
%two-area system using the standard 6th-order round-rotor (GENROU) model.
%
%   RESULT = kundur_ex126_genrou_ssa() runs the in-house Newton-Raphson
%   power flow on +cases/case_kundur_two_area_classical, then assembles a
%   24-state linearised model (6 states x 4 generators). The reduced state
%   matrix is obtained by Schur complement; eigenvalues are compared with
%   Kundur Table E12.3.
%
%   State vector per machine i (manual excitation, E_fd constant):
%       x_i = [ delta_i ; omega_i ; E'qi ; E'di ; psi'1di ; psi'2qi ]
%
%   Reference: PowerWorld, "Description of Machine Models GENROU, GENSAL,
%   GENTPF and GENTPJ", 2018 (derived from Sauer & Pai, Ch. 3, 2006).
%   The implementation uses standard GENROU damper-flux states and
%   gamma-coupled subtransient EMFs as algebraic outputs:
%       E''q = gamma_d1 psi'1d + (1-gamma_d1) E'q
%       E''d = gamma_q1 psi'2q + (1-gamma_q1) E'd
%   with gamma_d1 = (X''d - Xl)/(X'd - Xl), gamma_q1 = (X''q - Xl)/(X'q - Xl),
%   and stator equations in generator-current convention:
%       Vd = E''d - Ra Id + X''q Iq
%       Vq = E''q - Ra Iq - X''d Id

pf = [];
opts = struct();
if nargin >= 2 && strcmpi(varargin{1}, 'pf')
    pf = varargin{2};
    if nargin >= 4 && strcmpi(varargin{3}, 'options'); opts = varargin{4}; end
elseif nargin >= 2 && strcmpi(varargin{1}, 'options')
    opts = varargin{2};
end
% Model options (defaults reproduce the original Sauer-Pai behaviour).
if ~isfield(opts, 'load_model');  opts.load_model  = 'cc_p_cz_q'; end
if ~isfield(opts, 'use_saturation'); opts.use_saturation = false; end
if ~isfield(opts, 'sat_params')
    opts.sat_params = struct('Asat',0.015,'Bsat',9.6,'PsiT1',0.9);
end
if ~isfield(opts, 'fd_eps'); opts.fd_eps = 1e-6; end
if ~isfield(opts, 'sat_q_axis'); opts.sat_q_axis = true; end   % q-axis saturation on/off
if ~isfield(opts, 'sat_scale'); opts.sat_scale = 1.0; end       % multiplier on Se
if ~isfield(opts, 'machine_override'); opts.machine_override = []; end

if isempty(pf)
    case_data = cases.case_kundur_two_area_classical();
    pf_opts = struct('plot_results', false, 'verbose', false, ...
        'max_iter', 50, 'tolerance', 1e-8, 'enforce_q_limits', false);
    pf = pfsolver.powerflow_newton_raphson(case_data, pf_opts);
end
case_data = cases.case_kundur_two_area_classical();
if ~isempty(opts.machine_override)
    case_data.machines = opts.machine_override;
end
M = case_data.machines;
if ~pf.converged
    error('kundur_ex126_kundur_ssa:noConvergence', ...
        'Power-flow did not converge.');
end

% gamma factors (constant, machine pu)
R = M.reactances;
g_d1 = (R.Xdpp - R.Xl) / (R.Xdp - R.Xl);
g_q1 = (R.Xqpp - R.Xl) / (R.Xqp - R.Xl);
g_d2 = (1 - g_d1) / (R.Xdp - R.Xl);
g_q2 = (1 - g_q1) / (R.Xqp - R.Xl);
gamma = struct('d1',g_d1,'q1',g_q1,'d2',g_d2,'q2',g_q2);

[init, Ynet] = initialise_generators(pf, case_data, M, gamma, opts);
init_pf = init;
[Te_pf, Id_pf, Iq_pf, Vd_pf, Vq_pf] = te_at_op(init_pf.x0, init_pf.y0, init_pf, M, Ynet, case_data.base_values, gamma, init_pf.zb_scale);
init_pf.Tm = Te_pf; init_pf.Id = Id_pf; init_pf.Iq = Iq_pf; init_pf.Vd = Vd_pf; init_pf.Vq = Vq_pf;
pre_residual_f = dae_f(init_pf.x0, init_pf.y0, init_pf, M, Ynet, case_data.base_values, gamma);
pre_residual_g = dae_g(init_pf.x0, init_pf.y0, init_pf, M, Ynet, case_data.base_values, gamma, init_pf.zb_scale);
for refine_pass = 1:4
    init = refine_initial_state(init, M, Ynet, case_data.base_values, gamma);
    if init.newton_residual < 1e-9
        break;
    end
end
init.refine_passes = refine_pass;

[Jxx, Jxy, Jyx, Jyy] = build_dae_jacobian(init, M, Ynet, case_data.base_values, gamma);
% Form the Schur complement eliminating ALL algebraic variables.  The slack
% bus is NOT pinned here: the constant-current P load (Kundur Example a)
% provides a current path to ground, so Jyy is well-conditioned (cond ~ 40)
% without fixing a bus angle.  Pinning the slack-bus voltage (as the original
% free_y = setdiff(1:ny,2) did) treats the slack as an infinite bus and makes
% the generator centre-of-inertia (COI) mode oscillate against it through the
% transformer reactances, producing a spurious fast pair (~j48 classical,
% ~-299 full) and a wrong sign on the interarea damping.  Keeping every
% algebraic variable free lets the COI mode sit at (near) zero, matching the
% autonomous-system structure of Kundur Table E12.3.
free_y = 1:size(Jyy,1);
Ared_full = Jxx - Jxy(:,free_y) * (Jyy(free_y,free_y) \ Jyx(free_y,:));
% Reduce to the centre-of-inertia (COI) reference frame so the autonomous
% angle/speed redundancy is removed cleanly.  The kept states are, per
% machine: (delta_i - delta_COI), (omega_i - omega_COI), E'qi, E'di,
% psi''di, psi''qi  -- i.e. 6*ng - 2 states.
[Ared, keep, T_coi] = reduce_reference_angle(Ared_full, init.ng, init.H_sys);

lambda_full = eig(Ared_full);
[Vfull, ~] = eig(Ared_full);
lambda_reduced = eig(Ared);
[Vreduced, ~] = eig(Ared);

result = struct();
result.Afull = Ared_full;
result.Ared = Ared;
result.Jxx = Jxx; result.Jxy = Jxy; result.Jyx = Jyx; result.Jyy = Jyy;
result.free_y = 1:size(Jyy,1);
result.Ynet = Ynet;
result.eigenvalues = lambda_full;
result.reduced_eigenvalues = lambda_reduced;
result.state_names = init.state_names;
result.reduced_state_names = make_coi_state_names(M, init.ng);
result.init = init;
result.mode_shapes = Vfull;
result.reduced_mode_shapes = Vreduced;
result.frequency_Hz = abs(imag(lambda_full)) / (2*pi);
result.damping_ratio = -real(lambda_full) ./ (abs(lambda_full) + eps);
result.stable = all(real(lambda_full) < -1e-9);
result.reduced_frequency_Hz = abs(imag(lambda_reduced)) / (2*pi);
result.reduced_damping_ratio = -real(lambda_reduced) ./ (abs(lambda_reduced) + eps);
result.reduced_stable = all(real(lambda_reduced) < -1e-9);
result.gamma = gamma;
result.debug_residual_f = dae_f(init.x0, init.y0, init, M, Ynet, case_data.base_values, gamma);
result.debug_residual_g = dae_g(init.x0, init.y0, init, M, Ynet, case_data.base_values, gamma, init.zb_scale);
result.pre_refine_residual_f = pre_residual_f;
result.pre_refine_residual_g = pre_residual_g;
result.newton_iterations = init.newton_iterations;
result.newton_residual = init.newton_residual;
ref = stability.kundur_ex126_classical_analysis();
result.reference = ref;
end

% =========================================================================
function [Arel, keep, T] = reduce_reference_angle(Afull, ng, H_sys)
%REDUCE_REFERENCE_ANGLE  Project onto the COI (centre-of-inertia) reference
%frame so the autonomous angle/speed redundancy of the multi-machine system
%is removed cleanly.
%
%   The full state is, per machine k (6 states):
%       [ delta_k ; omega_k ; E'q_k ; E'd_k ; psi'1d_k ; psi'2q_k ]
%   The COI angle/speed are  delta_COI = sum(H_k delta_k)/sum(H_k),
%                            omega_COI = sum(H_k omega_k)/sum(H_k).
%   To avoid the linear dependence among the 4 relative angles
%   (sum(H_k*(delta_k-delta_COI)) = 0), the reduced state is taken as:
%       machine 1:        E'q_1, E'd_1, psi'1d_1, psi'2q_1   (4 states)
%       machine k=2..ng:   delta_k-delta_COI, omega_k-omega_COI,
%                          E'q_k, E'd_k, psi'1d_k, psi'2q_k  (6 states each)
%   giving 4 + 6*(ng-1) = 6*ng - 2 reduced states.  T maps reduced -> full;
%   L = T^+ (pseudoinverse) maps full derivatives -> reduced derivatives;
%   Arel = L * Afull * T.
if nargin < 3 || isempty(H_sys)
    H_sys = ones(ng,1);
end
Hn = H_sys(:) / sum(H_sys);
nx = size(Afull,1);
nred = 6*ng - 2;
T = zeros(nx, nred);
keep = false(nx,1);
c = 1;
% Machine 1: keep only the 4 flux states (delta_1, omega_1 absorbed into COI)
for s = 3:6
    T((0)*6+s, c) = 1;
    keep((0)*6+s) = true;
    c = c + 1;
end
% Machines 2..ng: relative angle, relative speed, and 4 flux states
for k = 2:ng
    % delta_k - delta_COI
    T((k-1)*6+1, c) = 1;
    for kk = 1:ng
        T((kk-1)*6+1, c) = T((kk-1)*6+1, c) - Hn(kk);
    end
    keep((k-1)*6+1) = true;
    c = c + 1;
    % omega_k - omega_COI
    T((k-1)*6+2, c) = 1;
    for kk = 1:ng
        T((kk-1)*6+2, c) = T((kk-1)*6+2, c) - Hn(kk);
    end
    keep((k-1)*6+2) = true;
    c = c + 1;
    % E'q, E'd, psi''d, psi''q (unchanged)
    for s = 3:6
        T((k-1)*6+s, c) = 1;
        keep((k-1)*6+s) = true;
        c = c + 1;
    end
end
keep = find(keep);
L = pinv(T);
Arel = L * Afull * T;
end

% =========================================================================
function names = make_coi_state_names(M, ng)
%MAKE_COI_STATE_NAMES  Names for the 6*ng-2 COI-reduced states:
%   per machine: (delta-delta_COI), (omega-omega_COI), E'q, E'd, psi'1d, psi'2q.
names = cell(6*ng-2, 1);
c = 1;
for k = 1:ng
    gid = M.units(k).gen_id;
    names{c} = sprintf('\\delta_{%s}-\\delta_{COI}', gid); c = c+1;
    names{c} = sprintf('\\omega_{%s}-\\omega_{COI}', gid); c = c+1;
    names{c} = sprintf("E'_{q,%s}", gid); c = c+1;
    names{c} = sprintf("E'_{d,%s}", gid); c = c+1;
    names{c} = sprintf("\\psi'_{1d,%s}", gid); c = c+1;
    names{c} = sprintf("\\psi'_{2q,%s}", gid); c = c+1;
end
end

% =========================================================================
function [init, Ynet] = initialise_generators(pf, case_data, M, gamma, opts)
if nargin < 5 || isempty(opts); opts = struct('load_model','cc_p_cz_q'); end
w0 = 2*pi*case_data.base_values.frequency_Hz;
Sbase = case_data.base_values.S_base_MVA;
Sm = M.base.S_MVA;
% Machine dynamic data are on 900 MVA machine base. The network is on
% 100 MVA system base; generator terminal voltage bases are already handled
% by the transformer per-unit conversion in the case data, so only the MVA
% base conversion is required here.
zb_scale = Sbase / Sm;

ng = numel(M.units);
R = M.reactances;
init.opts = opts;
init.state_names = cell(ng*6, 1);
x0 = zeros(ng*6, 1);
init.delta = zeros(ng,1);
init.Efd = zeros(ng,1);
init.bus_idx = zeros(ng,1);
init.Id = zeros(ng,1); init.Iq = zeros(ng,1);
init.Vd = zeros(ng,1); init.Vq = zeros(ng,1);
init.Eqpi = zeros(ng,1); init.Edpi = zeros(ng,1);
init.Psipd = zeros(ng,1); init.Psipq = zeros(ng,1);
init.H_sys = zeros(ng,1);

for k = 1:ng
    bidx = find(pf.external_bus_ids == M.units(k).bus, 1);
    init.bus_idx(k) = bidx;
    Vmag = pf.bus_voltage(bidx);
    Vang = deg2rad(pf.bus_angle_deg(bidx));
    Vt = Vmag * exp(1i*Vang);
    Sgen = pf.P_generation(bidx) + 1i*pf.Q_generation(bidx);
    It_net = conj(Sgen / Vt);

    Xd_n=R.Xd*zb_scale; Xdp_n=R.Xdp*zb_scale; Xdpp_n=R.Xdpp*zb_scale;
    Xq_n=R.Xq*zb_scale; Xqp_n=R.Xqp*zb_scale; Xqpp_n=R.Xqpp*zb_scale;
    Xl_n=R.Xl*zb_scale; Ra_n=R.Ra*zb_scale;

    % Rotor angle from the q-axis steady-state condition:
    %   E'd = (Xq-X'q) Iq and Vd = E'd - Ra Id + X'q Iq
    % therefore Vd + Ra Id - Xq Iq = 0.
    delta_guess = angle(Vt + (Ra_n + 1i*Xd_n) * It_net);
    A = real(Vt) + Ra_n*real(It_net) - Xq_n*imag(It_net);
    B = -imag(Vt) - Ra_n*imag(It_net) - Xq_n*real(It_net);
    roots_delta = [atan2(-B, A), atan2(-B, A)+pi, atan2(-B, A)-pi];
    % Pick the generator convention root: positive q-axis current and
    % positive q-axis transient EMF. If both roots pass, use the one closest
    % to the classical voltage-behind-Xd estimate.
    scores = inf(size(roots_delta));
    for rr = 1:numel(roots_delta)
        dtest = roots_delta(rr);
        Id_t = sin(dtest)*real(It_net) - cos(dtest)*imag(It_net);
        Iq_t = cos(dtest)*real(It_net) + sin(dtest)*imag(It_net);
        Vq_t = cos(dtest)*real(Vt) + sin(dtest)*imag(Vt);
        Eqp_t = Vq_t - Ra_n*Iq_t - Xdp_n*Id_t;
        scores(rr) = abs(angle(exp(1i*(dtest - delta_guess))));
        if Iq_t <= 0 || Eqp_t <= 0
            scores(rr) = scores(rr) + 10;
        end
    end
    [~, iroot] = min(scores);
    delta = roots_delta(iroot);
    init.delta(k) = delta;
    Id = sin(delta)*real(It_net) - cos(delta)*imag(It_net);
    Iq = cos(delta)*real(It_net) + sin(delta)*imag(It_net);
    Vd = sin(delta)*real(Vt) - cos(delta)*imag(Vt);
    Vq = cos(delta)*real(Vt) + sin(delta)*imag(Vt);
    init.Id(k)=Id; init.Iq(k)=Iq; init.Vd(k)=Vd; init.Vq(k)=Vq;

    % Air-gap fluxes psi_2d = E''q, psi_2q = E''d, fixed by the stator
    % equations (generator-current convention):
    %   Vq = E''q - Ra Iq - X''d Id  =>  E''q = Vq + Ra Iq + X''d Id
    %   Vd = E''d - Ra Id + X''q Iq  =>  E''d = Vd + Ra Id - X''q Iq
    % These are independent of saturation.
    psi2d = Vq + Ra_n*Iq + Xdpp_n*Id;
    psi2q = Vd + Ra_n*Id - Xqpp_n*Iq;
    [Se0, gqd0] = sat_factor(psi2d, psi2q, init, R, zb_scale);
    % GENROU equilibrium must satisfy the same damper-flux equations used
    % below in dae_f.  Consequently
    %   psi'1d = E'q + (X'd-Xl)Id,
    %   E''q   = gd1*E'q + (1-gd1)*psi'1d
    %           = E'q + (X'd-X''d)Id,
    % and similarly
    %   psi'2q = -E'd + (X'q-Xl)Iq,
    %   E''d   = (2*gq1-1)E'd + (1-gq1)(X'q-Xl)Iq.
    % Do not substitute X''-Xl here: that violates the state equations and
    % produces a non-equilibrium DAE.
    Eqp = psi2d - (Xdp_n - Xdpp_n)*Id;
    Psipd = Eqp + (Xdp_n - Xl_n)*Id;
    Edp = (psi2q - (1-gamma.q1)*(Xqp_n-Xl_n)*Iq) / (2*gamma.q1 - 1);
    Psipq = -Edp + (Xqp_n - Xl_n)*Iq;
    gamma_d2_n = (1-gamma.d1)/(Xdp_n-Xl_n);
    Id_eff0 = gamma.d1*Id + gamma_d2_n*(Eqp - Psipd);
    Eq = Eqp + (Xd_n - Xdp_n)*Id_eff0;
    init.Efd(k) = Eq;
    init.Eqpi(k)=Eqp; init.Edpi(k)=Edp;
    init.Psipd(k)=Psipd; init.Psipq(k)=Psipq;

    x0((k-1)*6+1)=delta; x0((k-1)*6+2)=0;
    x0((k-1)*6+3)=Eqp; x0((k-1)*6+4)=Edp;
    x0((k-1)*6+5)=Psipd; x0((k-1)*6+6)=Psipq;

    init.state_names{(k-1)*6+1} = sprintf('\\delta_{%s}', M.units(k).gen_id);
    init.state_names{(k-1)*6+2} = sprintf('\\omega_{%s}', M.units(k).gen_id);
    init.state_names{(k-1)*6+3} = sprintf("E'_{q,%s}", M.units(k).gen_id);
    init.state_names{(k-1)*6+4} = sprintf("E'_{d,%s}", M.units(k).gen_id);
    init.state_names{(k-1)*6+5} = sprintf("\\psi'_{1d,%s}", M.units(k).gen_id);
    init.state_names{(k-1)*6+6} = sprintf("\\psi'_{2q,%s}", M.units(k).gen_id);
    init.H_sys(k) = M.units(k).H * (Sm/Sbase);
end
init.x0 = x0; init.ng = ng; init.w0 = w0;
init.zb_scale = zb_scale;

Ynet = build_network_admittance(pf, case_data, M, init.opts);

init.algebraic_names = {};
for b = 1:numel(pf.external_bus_ids)
    init.algebraic_names{end+1} = sprintf('Vre_%d', pf.external_bus_ids(b));
    init.algebraic_names{end+1} = sprintf('Vim_%d', pf.external_bus_ids(b));
end
init.y0 = zeros(2*numel(pf.external_bus_ids), 1);
for b = 1:numel(pf.external_bus_ids)
    V = pf.bus_voltage(b) * exp(1i*deg2rad(pf.bus_angle_deg(b)));
    init.y0(2*b-1) = real(V);
    init.y0(2*b  ) = imag(V);
end
end

% =========================================================================
function Ynet = build_network_admittance(pf, case_data, M, opts)
if nargin < 4 || isempty(opts); opts = struct('load_model','cc_p_cz_q'); end
nb = numel(pf.external_bus_ids);
Y = complex(zeros(nb), zeros(nb));
LD = case_data.line_data;
for l = 1:size(LD,1)
    f = find(pf.external_bus_ids == LD(l,1), 1);
    t = find(pf.external_bus_ids == LD(l,2), 1);
    z = complex(LD(l,3), LD(l,4)); y = 1/z;
    Y(f,f)=Y(f,f)+y+1i*LD(l,5); Y(t,t)=Y(t,t)+y+1i*LD(l,5);
    Y(f,t)=Y(f,t)-y; Y(t,f)=Y(t,f)-y;
end
BD = case_data.bus_data;
for k = 1:size(BD,1)
    b = find(pf.external_bus_ids == BD(k,1), 1);
    Y(b,b) = Y(b,b) + 1i*BD(k,10);
    Pload=BD(k,7); Qload=BD(k,8); Vmag=pf.bus_voltage(b);
    if Vmag>0
        switch lower(opts.load_model)
            case {'cz','cz_p_cz_q'}
                % Full constant-impedance load: P as conductance, Q as
                % susceptance.  Sign convention: load draws current, so the
                % equivalent shunt admittance is Y_load = conj(S_load)/|V|^2
                % = (P - jQ)/|V|^2.
                if Pload~=0; Y(b,b) = Y(b,b) + Pload/(Vmag^2); end
                if Qload~=0; Y(b,b) = Y(b,b) - 1i*Qload/(Vmag^2); end
            case {'cc','cc_p_cc_q'}
                % Full constant-current: no shunt admittance; both P and Q
                % injected as current in dae_g.
            otherwise
                % Kundur Example a: const-current P (in dae_g), const-impedance Q.
                if Qload~=0; Y(b,b) = Y(b,b) - 1i*Qload/(Vmag^2); end
        end
    end
end
Ynet = Y;
end

% =========================================================================
function init = refine_initial_state(init, M, Ynet, base, gamma)
x = init.x0; y = init.y0;
zb_scale = init.zb_scale;
ng = init.ng;
% Tm = Te at operating point
[Te0, Id0, Iq0, Vd0, Vq0] = te_at_op(x, y, init, M, Ynet, base, gamma, zb_scale);
init.Tm = Te0; init.Id=Id0; init.Iq=Iq0; init.Vd=Vd0; init.Vq=Vq0;
Efd = init.Efd; Tm = init.Tm;

% Free unknowns: machine states (except slack delta), bus voltages (except
% slack imaginary part), and the per-machine inputs Efd and Tm.  Treating
% Efd and Tm as free lets the saturated equilibrium be found without shifting
% the power-flow operating point: f(3)=0 pins Efd, f(2)=0 pins Tm.
fixed_y = 2; free_y = setdiff(1:numel(y), fixed_y);
fixed_x = 1; free_x = setdiff(1:numel(x), fixed_x);
maxit = 200; tol = 1e-12; eps_p = 1e-6;
res_f = @(xx,yy,ee,tt) dae_f_param(xx,yy,ee,tt,init,M,Ynet,base,gamma);
res_g = @(xx,yy) dae_g(xx,yy,init,M,Ynet,base,gamma,zb_scale);
for it = 1:maxit
    f = res_f(x,y,Efd,Tm);
    g = res_g(x,y);
    res = [f; g]; nr = norm(res);
    if nr < tol; break; end
    nx_free=numel(free_x); ny_free=numel(free_y); nefd=ng; ntm=ng;
    ntot = nx_free+ny_free+nefd+ntm;
    J = zeros(numel(f)+numel(g), ntot);
    for ii=1:nx_free
        i=free_x(ii); xp=x; xp(i)=xp(i)+eps_p; xm=x; xm(i)=xm(i)-eps_p;
        J(:,ii)=([res_f(xp,y,Efd,Tm);res_g(xp,y)]-[res_f(xm,y,Efd,Tm);res_g(xm,y)])/(2*eps_p);
    end
    for jj=1:ny_free
        j=free_y(jj); yp=y; yp(j)=yp(j)+eps_p; ym=y; ym(j)=ym(j)-eps_p;
        J(:,nx_free+jj)=([res_f(x,yp,Efd,Tm);res_g(x,yp)]-[res_f(x,ym,Efd,Tm);res_g(x,ym)])/(2*eps_p);
    end
    for kk=1:nefd
        ep=Efd; ep(kk)=ep(kk)+eps_p; em=Efd; em(kk)=em(kk)-eps_p;
        J(:,nx_free+ny_free+kk)=([res_f(x,y,ep,Tm);res_g(x,y)]-[res_f(x,y,em,Tm);res_g(x,y)])/(2*eps_p);
    end
    for kk=1:ntm
        tp=Tm; tp(kk)=tp(kk)+eps_p; tm=Tm; tm(kk)=tm(kk)-eps_p;
        J(:,nx_free+ny_free+nefd+kk)=([res_f(x,y,Efd,tp);res_g(x,y)]-[res_f(x,y,Efd,tm);res_g(x,y)])/(2*eps_p);
    end
    step = (J'*J + 1e-10*eye(ntot)) \ (J'*(-res));
    lambda = 0; res_new = inf; st = step;
    for tries = 1:15
        if lambda>0; st = (J'*J + lambda*eye(ntot)) \ (J'*(-res)); end
        x_new=x; x_new(free_x)=x_new(free_x)+st(1:nx_free);
        y_new=y; y_new(free_y)=y_new(free_y)+st(nx_free+1:nx_free+ny_free);
        Efd_new=Efd + st(nx_free+ny_free+1:nx_free+ny_free+nefd);
        Tm_new=Tm + st(nx_free+ny_free+nefd+1:end);
        rn = norm([res_f(x_new,y_new,Efd_new,Tm_new);res_g(x_new,y_new)]);
        if rn < nr; x=x_new; y=y_new; Efd=Efd_new; Tm=Tm_new; res_new=rn; break; end
        if lambda==0; lambda=1e-8; else; lambda=lambda*10; end
    end
    if res_new >= nr; break; end
end
init.x0=x; init.y0=y; init.Efd=Efd; init.Tm=Tm; init.newton_iterations=it;
% Refresh constant operating inputs at the final equilibrium candidate.
[Te1, Id1, Iq1, Vd1, Vq1] = te_at_op(x, y, init, M, Ynet, base, gamma, zb_scale);
init.Tm = Te1; init.Id = Id1; init.Iq = Iq1; init.Vd = Vd1; init.Vq = Vq1;
f_final = dae_f(init.x0, init.y0, init, M, Ynet, base, gamma);
g_final = dae_g(init.x0, init.y0, init, M, Ynet, base, gamma, zb_scale);
init.newton_residual = norm([f_final; g_final]);
end

% =========================================================================
function f = dae_f_param(x, y, Efd, Tm, init, M, Ynet, base, gamma)
%DAE_F_PARAM Variant of dae_f with explicit Efd/Tm inputs (for the refine
%solve that treats them as free variables).
init.Efd = Efd; init.Tm = Tm;
f = dae_f(x, y, init, M, Ynet, base, gamma);
end

% =========================================================================
function [Te, Id_o, Iq_o, Vd_o, Vq_o] = te_at_op(x, y, init, M, Ynet, base, gamma, zb_scale)
R=M.reactances; ng=init.ng; nb=numel(y)/2;
V_bus=complex(zeros(nb,1),zeros(nb,1));
for b=1:nb; V_bus(b)=complex(y(2*b-1),y(2*b)); end
Te=zeros(ng,1); Id_o=zeros(ng,1); Iq_o=zeros(ng,1); Vd_o=zeros(ng,1); Vq_o=zeros(ng,1);
for k=1:ng
    [Id,Iq,Vd,Vq] = solve_stator(x,y,init,k,R,gamma,zb_scale);
    Ra_n = R.Ra * zb_scale;
    Te(k)=Vq*Iq+Vd*Id+Ra_n*(Id^2+Iq^2); Id_o(k)=Id; Iq_o(k)=Iq; Vd_o(k)=Vd; Vq_o(k)=Vq;
end
end

% =========================================================================
function [Id, Iq, Vd, Vq] = solve_stator(x, y, init, k, R, gamma, zb_scale)
% Solve stator currents from Sauer-Pai gamma-coupled subtransient EMFs using
% the generator-current convention used by the power-flow solver.
nb = numel(y)/2;
V_bus = complex(zeros(nb,1), zeros(nb,1));
for b = 1:nb
    V_bus(b) = complex(y(2*b-1), y(2*b));
end
bidx = init.bus_idx(k);
Vt = V_bus(bidx);
delta = x((k-1)*6+1);
Eqp = x((k-1)*6+3);
Edp = x((k-1)*6+4);
Psipd = x((k-1)*6+5);
Psipq = x((k-1)*6+6);
Xdpp_n = R.Xdpp * zb_scale;
Xqpp_n = R.Xqpp * zb_scale;
Ra_n = R.Ra * zb_scale;
Vd = sin(delta)*real(Vt) - cos(delta)*imag(Vt);
Vq = cos(delta)*real(Vt) + sin(delta)*imag(Vt);
Eqpp = gamma.d1*Eqp + (1-gamma.d1)*Psipd;
Edpp = gamma.q1*Edp + (1-gamma.q1)*Psipq;
rhs_d = Vd - Edpp;
rhs_q = Vq - Eqpp;
det = Xdpp_n*Xqpp_n + Ra_n*Ra_n;
Id = (-Ra_n*rhs_d - Xqpp_n*rhs_q) / det;
Iq = ( Xdpp_n*rhs_d - Ra_n*rhs_q) / det;
end

% =========================================================================
function [Jxx, Jxy, Jyx, Jyy] = build_dae_jacobian(init, M, Ynet, base, gamma)
eps_p=1e-6; nx=numel(init.x0); ny=numel(init.y0);
Jxx=zeros(nx,nx); Jxy=zeros(nx,ny); Jyx=zeros(ny,nx); Jyy=zeros(ny,ny);
x0=init.x0; y0=init.y0;
for i=1:nx
    xp=x0; xp(i)=xp(i)+eps_p; xm=x0; xm(i)=xm(i)-eps_p;
    Jxx(:,i)=(dae_f(xp,y0,init,M,Ynet,base,gamma)-dae_f(xm,y0,init,M,Ynet,base,gamma))/(2*eps_p);
    Jyx(:,i)=(dae_g(xp,y0,init,M,Ynet,base,gamma,init.zb_scale)-dae_g(xm,y0,init,M,Ynet,base,gamma,init.zb_scale))/(2*eps_p);
end
for j=1:ny
    yp=y0; yp(j)=yp(j)+eps_p; ym=y0; ym(j)=ym(j)-eps_p;
    Jxy(:,j)=(dae_f(x0,yp,init,M,Ynet,base,gamma)-dae_f(x0,ym,init,M,Ynet,base,gamma))/(2*eps_p);
    Jyy(:,j)=(dae_g(x0,yp,init,M,Ynet,base,gamma,init.zb_scale)-dae_g(x0,ym,init,M,Ynet,base,gamma,init.zb_scale))/(2*eps_p);
end
end

% =========================================================================
function f = dae_f(x, y, init, M, Ynet, base, gamma)
w0=init.w0; R=M.reactances; TC=M.time_constants;
Sbase=base.S_base_MVA; Sm=M.base.S_MVA; ng=init.ng;
zb_scale=Sbase/Sm;
f=zeros(6*ng,1);
nb=numel(init.y0)/2;
V_bus=complex(zeros(nb,1),zeros(nb,1));
for b=1:nb; V_bus(b)=complex(y(2*b-1),y(2*b)); end
for k=1:ng
    bidx=init.bus_idx(k);
    Vt=V_bus(bidx);
    delta=x((k-1)*6+1); omega_dev=x((k-1)*6+2);
    Eqp=x((k-1)*6+3); Edp=x((k-1)*6+4);
    Psipd=x((k-1)*6+5); Psipq=x((k-1)*6+6);
    Xd_n=R.Xd*zb_scale; Xdp_n=R.Xdp*zb_scale; Xdpp_n=R.Xdpp*zb_scale;
    Xq_n=R.Xq*zb_scale; Xqp_n=R.Xqp*zb_scale; Xqpp_n=R.Xqpp*zb_scale;
    Xl_n=R.Xl*zb_scale; Ra_n=R.Ra*zb_scale;
    Vd=sin(delta)*real(Vt)-cos(delta)*imag(Vt);
    Vq=cos(delta)*real(Vt)+sin(delta)*imag(Vt);
    Eqpp = gamma.d1*Eqp + (1-gamma.d1)*Psipd;
    Edpp = gamma.q1*Edp + (1-gamma.q1)*Psipq;
    % Stator algebraic equations, generator current convention (standard
    % PSAT/GENROU/MATLAB Model 2.1 form): Id, Iq are currents OUT of the
    % machine, consistent with the network injection Ig = conj(Sgen/Vt).
    %   Vd = E''d - Ra*Id + X''q*Iq
    %   Vq = E''q - X''d*Id - Ra*Iq
    % Solver below inverts this 2x2 system for Id, Iq.
    rhs_d = Vd - Edpp;
    rhs_q = Vq - Eqpp;
    det = Xdpp_n*Xqpp_n + Ra_n*Ra_n;
    Id = (-Ra_n*rhs_d - Xqpp_n*rhs_q ) / det;
    Iq = ( Xdpp_n*rhs_d - Ra_n*rhs_q ) / det;
    Te = Vq*Iq + Vd*Id + Ra_n*(Id^2+Iq^2);
    if isfield(init,'Tm') && ~isempty(init.Tm); Tm=init.Tm(k); else
        Tm=init.Vq(k)*init.Iq(k)+init.Vd(k)*init.Id(k); end
    H=init.H_sys(k); D=M.units(k).D*(Sm/Sbase);
    f((k-1)*6+1)=omega_dev*w0;
    f((k-1)*6+2)=(Tm-Te-D*omega_dev)/(2*H);
    gamma_d2_n = (1-gamma.d1) / (Xdp_n - Xl_n);
    gamma_q2_n = (1-gamma.q1) / (Xqp_n - Xl_n);
    % Standard GENROU effective currents (PowerWorld 2018, generator convention):
    %   Id_eff = gd1 Id + gd2 (E'q - psi'1d)
    %   Iq_eff = gq1 Iq - gq2 (psi'2q + E'd)
    Id_eff = gamma.d1*Id + gamma_d2_n*(Eqp - Psipd);
    Iq_eff = gamma.q1*Iq - gamma_q2_n*(Psipq + Edp);
    % Magnetic saturation (Kundur / colib GENROU).  The air-gap flux
    % components psi_2d, psi_2q are exactly the gamma-coupled subtransient
    % EMFs Eqpp, Edpp.  Se = Bsat*(|psi_2|-PsiT1)^2/|psi_2| for |psi_2|>=PsiT1.
    % Saturation adds -Se*psi_2d to the d-axis transient equation and
    % -Se*gqd*psi_2q to the q-axis transient equation, where
    % gqd = (Xq-Xl)/(Xd-Xl).  The q-axis term can be disabled for a
    % d-axis-only (GENSAL-style) saturation.
    [Se, gqd] = sat_factor(Eqpp, Edpp, init, R, zb_scale);
    sat_q = isfield(init,'opts') && isfield(init.opts,'sat_q_axis') ...
        && init.opts.sat_q_axis;
    if ~sat_q; gqd = 0; end
    f((k-1)*6+3)=(init.Efd(k)-Eqp-(Xd_n-Xdp_n)*Id_eff-Se*Eqpp)/TC.Tpd0;
    f((k-1)*6+4)=(-Edp+(Xq_n-Xqp_n)*Iq_eff-Se*gqd*Edpp)/TC.Tpq0;
    % Standard GENROU subtransient damper equations (PowerWorld 2018):
    %   T''do d(psi'1d)/dt = -psi'1d + E'q + (X'd-Xl) Id
    %   T''qo d(psi'2q)/dt = -psi'2q - E'd + (X'q-Xl) Iq
    f((k-1)*6+5)=(-Psipd+Eqp+(Xdp_n-Xl_n)*Id)/TC.Tppd0;
    f((k-1)*6+6)=(-Psipq-Edp+(Xqp_n-Xl_n)*Iq)/TC.Tppq0;
end
end

% =========================================================================
function [Se, gqd] = sat_factor(Eqpp, Edpp, init, R, zb_scale)
%SAT_FACTOR Kundur/colib saturation function Se(|psi_2|).
%  Se(psi) = Bsat*(psi - PsiT1)^2 / psi   for psi > PsiT1, else 0.
%  PsiT1 is the saturation knee (0.9 pu for the Kundur two-area machines).
%  Asat is retained as the small-signal S(1.0) calibration value for
%  reporting but does not enter the active formula.
use_sat = isfield(init,'opts') && isfield(init.opts,'use_saturation') ...
    && init.opts.use_saturation;
sat_q = isfield(init,'opts') && isfield(init.opts,'sat_q_axis') ...
    && ~isempty(init.opts.sat_q_axis) && init.opts.sat_q_axis;
sat_scale = 1.0;
if isfield(init,'opts') && isfield(init.opts,'sat_scale'); sat_scale = init.opts.sat_scale; end
if sat_q
    gqd = (R.Xq - R.Xl) / (R.Xd - R.Xl);   % constant, machine pu
else
    gqd = 0;
end
if ~use_sat
    Se = 0;
    return;
end
PsiT1 = init.opts.sat_params.PsiT1;
Bsat  = init.opts.sat_params.Bsat;
% psi_2d, psi_2q are on the machine pu base (Eqpp/Edpp are gamma-coupled
% fluxes built from machine-base states), so |psi_2| is in machine pu.
psi2 = sqrt(Eqpp^2 + Edpp^2);
if psi2 > PsiT1
    Se = sat_scale * Bsat * (psi2 - PsiT1)^2 / (psi2 + 1e-6);
else
    Se = 0;
end
end

% =========================================================================
function g = dae_g(x, y, init, M, Ynet, base, gamma, zb_scale)
R=M.reactances; ng=init.ng; nb=numel(y)/2;
V_bus=complex(zeros(nb,1),zeros(nb,1));
for b=1:nb; V_bus(b)=complex(y(2*b-1),y(2*b)); end
Inet = Ynet * V_bus;
g = zeros(2*nb,1);
for b=1:nb; g(2*b-1)=-real(Inet(b)); g(2*b)=-imag(Inet(b)); end
case_data = cases.case_kundur_two_area_classical();
BD = case_data.bus_data;
load_model = 'cc_p_cz_q';
if isfield(init,'opts') && isfield(init.opts,'load_model') && ~isempty(init.opts.load_model)
    load_model = lower(init.opts.load_model);
end
for b = 1:nb
    Pload = BD(b,7);
    Qload = BD(b,8);
    if Pload ~= 0 || Qload ~= 0
        Vt = V_bus(b);
        Vop = abs(complex(init.y0(2*b-1), init.y0(2*b)));
        switch load_model
            case {'cz','cz_p_cz_q'}
                % Constant-impedance P and Q: handled as shunt admittance in
                % Ynet, so no extra current injection here.
            case {'cp','cp_p_cp_q','cp_p_cz_q'}
                % Constant-power load: I = conj(S/V).  The mismatch is written
                % as current balance, so the load current is conj(Sload/Vt).
                if abs(Vt) <= eps
                    Iload = 0;
                else
                    Iload = conj((Pload + 1i*Qload) / Vt);
                end
                g(2*b-1) = g(2*b-1) - real(Iload);
                g(2*b)   = g(2*b)   - imag(Iload);
            case {'cc','cc_p_cc_q'}
                % Full constant-current: magnitude S/Vop, angle follows Vt.
                if abs(Vt) <= eps || Vop <= eps
                    Iload = 0;
                else
                    Iload = ((Pload + 1i*Qload) / Vop) * (Vt / abs(Vt));
                end
                g(2*b-1) = g(2*b-1) - real(Iload);
                g(2*b)   = g(2*b)   - imag(Iload);
            otherwise
                % Kundur Example a: const-current P, const-impedance Q (Q is
                % already in Ynet).  P magnitude Pload/Vop, angle follows Vt.
                if abs(Vt) <= eps || Vop <= eps
                    Iload_p = 0;
                else
                    Iload_p = (Pload / Vop) * (Vt / abs(Vt));
                end
                g(2*b-1) = g(2*b-1) - real(Iload_p);
                g(2*b)   = g(2*b)   - imag(Iload_p);
        end
    end
end
for k=1:ng
    bidx=init.bus_idx(k);
    Vt=V_bus(bidx);
    delta=x((k-1)*6+1);
    Eqp=x((k-1)*6+3); Edp=x((k-1)*6+4);
    Psipd=x((k-1)*6+5); Psipq=x((k-1)*6+6);
    Xdpp_n=R.Xdpp*zb_scale; Xqpp_n=R.Xqpp*zb_scale; Ra_n=R.Ra*zb_scale;
    Vd=sin(delta)*real(Vt)-cos(delta)*imag(Vt);
    Vq=cos(delta)*real(Vt)+sin(delta)*imag(Vt);
    Eqpp=gamma.d1*Eqp+(1-gamma.d1)*Psipd;
    Edpp=gamma.q1*Edp+(1-gamma.q1)*Psipq;
    rhs_d=Vd-Edpp;
    rhs_q=Vq-Eqpp;
    det=Xdpp_n*Xqpp_n+Ra_n*Ra_n;
    Id=(-Ra_n*rhs_d-Xqpp_n*rhs_q)/det;
    Iq=(Xdpp_n*rhs_d-Ra_n*rhs_q)/det;
    Ire=sin(delta)*Id+cos(delta)*Iq;
    Iim=-cos(delta)*Id+sin(delta)*Iq;
    Ig=complex(Ire,Iim);
    g(2*bidx-1)=real(Ig)-real(Inet(bidx));
    g(2*bidx)=imag(Ig)-imag(Inet(bidx));
end
end
