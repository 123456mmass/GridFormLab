function result = kundur_ex126_book_flux_ssa(varargin)
%KUNDUR_EX126_BOOK_FLUX_SSA Independent flux/saturation realization of Kundur Example 12.6.
%two-area system using the full 6th-order Sauer-Pai synchronous-machine model.
%
%   RESULT = kundur_ex126_kundur_ssa() runs the in-house Newton-Raphson
%   power flow on +cases/kundur_ex126_book_case, then assembles a
%   24-state linearised model (6 states x 4 generators). The reduced state
%   matrix is obtained by Schur complement; eigenvalues are compared with
%   Kundur Table E12.3.
%
%   State vector per machine i (manual excitation, E_fd constant):
%       x_i = [ delta_i ; omega_i ; E'qi ; E'di ; E''qi ; E''di ]
%
%   Reference: Kundur, Power System Stability and Control; MATLAB GENTPJ.
%   This uses the Kundur/GENTPJ 6th-order realization in which the
%   subtransient EMFs E''q, E''d are the 5th/6th states (not the damper
%   fluxes psi_1d, psi_2q). With saturation disabled (Sd=Sq=0):
%       dE''q/dt = (E'q - E''q - Id*(X'd-X''d)) / T''d0
%       dE''d/dt = (E'd - E''d + Iq*(X'q-X''q)) / T''q0
%       dE'q/dt  = (Efd + E''q*(Xd-X'd)/(X'd-X''d) - E'q*(Xd-X''d)/(X'd-X''d)) / T'd0
%       dE'd/dt  = (E''d*(Xq-X'q)/(X'q-X''q) - E'd*(Xq-X''q)/(X'q-X''q)) / T'q0
%   and the stator algebraic equations (generator-current convention):
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
% Kundur lists Asat, Bsat, and PsiT1 in Example 12.6; the book-flux
% realization therefore includes saturation unless explicitly disabled.
if ~isfield(opts, 'use_saturation'); opts.use_saturation = true; end
if ~isfield(opts, 'sat_params')
    opts.sat_params = struct('Asat',0.015,'Bsat',9.6,'PsiT1',0.9);
end
% Central-difference plateau probe selects 3e-6; smaller steps show round-off.
if ~isfield(opts, 'fd_eps'); opts.fd_eps = 3e-6; end
if ~isfield(opts, 'sat_q_axis'); opts.sat_q_axis = true; end   % q-axis saturation on/off
if ~isfield(opts, 'sat_scale'); opts.sat_scale = 1.0; end       % multiplier on Se
if ~isfield(opts, 'machine_override'); opts.machine_override = []; end
if ~isfield(opts, 'line_charging_scale'); opts.line_charging_scale = 1.0; end
if ~isfield(opts, 'bus_shunt_scale'); opts.bus_shunt_scale = 1.0; end
if ~isfield(opts, 'qload_z_scale'); opts.qload_z_scale = 1.0; end
if ~isfield(opts, 'line_r_scale'); opts.line_r_scale = 1.0; end

if isempty(pf)
    case_data = cases.kundur_ex126_book_case();
    pf_opts = struct('plot_results', false, 'verbose', false, ...
        'max_iter', 50, 'tolerance', 1e-8, 'enforce_q_limits', false);
    pf = pfsolver.powerflow_newton_raphson(case_data, pf_opts);
end
case_data = cases.kundur_ex126_book_case();
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

[Jxx, Jxy, Jyx, Jyy] = build_dae_jacobian( ...
    init, M, Ynet, case_data.base_values, gamma, opts.fd_eps);
% Common case-agnostic DAE small-signal engine.  Kundur and Sauer-Pai now
% pass through the same Schur-complement/eigenvalue/COI-reduction code path;
% only the machine/network residual functions differ.
model = struct();
model.x0 = init.x0;
model.y0 = init.y0;
model.f = @(xx,yy) dae_f(xx, yy, init, M, Ynet, case_data.base_values, gamma);
model.g = @(xx,yy) dae_g(xx, yy, init, M, Ynet, case_data.base_values, gamma, init.zb_scale);
model.Jxx = Jxx; model.Jxy = Jxy; model.Jyx = Jyx; model.Jyy = Jyy;
model.free_y = 1:size(Jyy,1);
model.reduction = 'coi';
model.ng = init.ng;
model.states_per_machine = 6;
model.angle_state_index = 1;
model.speed_state_index = 2;
model.inertia = init.H_sys;
model.state_names = init.state_names;
model.metadata = struct('benchmark','Kundur Example 12.6 book-flux realization','engine','stability.multimachine_ssa');
core = stability.multimachine_ssa(model);

result = core;
result.Ynet = Ynet;
result.reduced_state_names = make_coi_state_names(M, init.ng);
result.init = init;
result.gamma = gamma;
result.debug_residual_f = dae_f(init.x0, init.y0, init, M, Ynet, case_data.base_values, gamma);
result.debug_residual_g = dae_g(init.x0, init.y0, init, M, Ynet, case_data.base_values, gamma, init.zb_scale);
result.pre_refine_residual_f = pre_residual_f;
result.pre_refine_residual_g = pre_residual_g;
result.newton_iterations = init.newton_iterations;
result.newton_residual = init.newton_residual;
result.fd_eps = opts.fd_eps;
ref = stability.kundur_ex126_classical_analysis();
result.reference = ref;
% Expose DAE functions for external calls (e.g. transient simulation):
result.dae_f = @dae_f;
result.dae_g = @dae_g;
end

% =========================================================================
function [Arel, keep, T] = reduce_reference_angle(Afull, ng, H_sys)
%REDUCE_REFERENCE_ANGLE  Project onto the COI (centre-of-inertia) reference
%frame so the autonomous angle/speed redundancy of the multi-machine system
%is removed cleanly.
%
%   The full state is, per machine k (6 states):
%       [ delta_k ; omega_k ; E'q_k ; E'd_k ; E''q_k ; E''d_k ]
%   The COI angle/speed are  delta_COI = sum(H_k delta_k)/sum(H_k),
%                            omega_COI = sum(H_k omega_k)/sum(H_k).
%   To avoid the linear dependence among the 4 relative angles
%   (sum(H_k*(delta_k-delta_COI)) = 0), the reduced state is taken as:
%       machine 1:        E'q_1, E'd_1, E''q_1, E''d_1   (4 states)
%       machine k=2..ng:   delta_k-delta_COI, omega_k-omega_COI,
%                          E'q_k, E'd_k, E''q_k, E''d_k  (6 states each)
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
    % E'q, E'd, E''q, E''d (unchanged)
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
%   per machine: (delta-delta_COI), (omega-omega_COI), E'q, E'd, E''q, E''d.
names = cell(6*ng-2, 1);
c = 1;
for k = 1:ng
    gid = M.units(k).gen_id;
    names{c} = sprintf('\\delta_{%s}-\\delta_{COI}', gid); c = c+1;
    names{c} = sprintf('\\omega_{%s}-\\omega_{COI}', gid); c = c+1;
    names{c} = sprintf("E'_{q,%s}", gid); c = c+1;
    names{c} = sprintf("E'_{d,%s}", gid); c = c+1;
    names{c} = sprintf("E''_{q,%s}", gid); c = c+1;
    names{c} = sprintf("E''_{d,%s}", gid); c = c+1;
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

    % Kundur Eq. (3.189): psi_I = Asat*exp(Bsat*(psi_at-PsiT1)).
    % The GENTPJ multiplier is Sat_d = 1 + psi_I/psi_at (not Asat,
    % and not a second 1+Sat_d).  psi_at is rotation invariant, so it is
    % determined directly from the verified PF phasors.
    delta_seed = angle(Vt + (Ra_n + 1i*Xd_n) * It_net);
    [Id_seed,Iq_seed] = stability.kundur_book_dq(It_net,delta_seed);
    [Vd_seed,Vq_seed] = stability.kundur_book_dq(Vt,delta_seed);
    [Satd0, Satq0] = book_saturation_factors_stator( ...
        Vd_seed, Vq_seed, init, R, zb_scale, Id_seed, Iq_seed);
    Xq_sat = Xl_n + (Xq_n-Xl_n)/Satq0;
    Xdp_sat = Xl_n + (Xdp_n-Xl_n)/Satd0;

    % At steady state the q-axis rotor equations require
    % Vd + Ra*Id - Xq_sat*Iq = 0.  This fixes delta directly from PF V,I;
    % no network-voltage refinement is involved.
    A = real(Vt) + Ra_n*real(It_net) - Xq_sat*imag(It_net);
    B = -imag(Vt) - Ra_n*imag(It_net) - Xq_sat*real(It_net);
    roots_delta = [atan2(-B,A), atan2(-B,A)+pi, atan2(-B,A)-pi];
    scores = inf(size(roots_delta));
    for rr = 1:numel(roots_delta)
        dtest = roots_delta(rr);
        [Id_t,Iq_t] = stability.kundur_book_dq(It_net,dtest);
        [~,Vq_t] = stability.kundur_book_dq(Vt,dtest);
        Eqp_t = Vq_t + Ra_n*Iq_t + Xdp_sat*Id_t;
        scores(rr) = abs(angle(exp(1i*(dtest-delta_seed))));
        if Iq_t <= 0 || Eqp_t <= 0; scores(rr) = scores(rr) + 10; end
    end
    [~,iroot] = min(scores);
    delta = roots_delta(iroot);
    init.delta(k) = delta;
    [Id,Iq] = stability.kundur_book_dq(It_net,delta);
    [Vd,Vq] = stability.kundur_book_dq(Vt,delta);
    [Satd0, Satq0] = book_saturation_factors_stator(Vd,Vq,init,R,zb_scale,Id,Iq);
    Xdpp_sat = Xl_n + (Xdpp_n-Xl_n)/Satd0;
    Xqpp_sat = Xl_n + (Xqpp_n-Xl_n)/Satq0;
    init.Id(k)=Id; init.Iq(k)=Iq; init.Vd(k)=Vd; init.Vq(k)=Vq;

    % Direct GENTPJ steady-state initialization.  These four assignments
    % make f(3:6)=0 identically under the same Sat_d/Sat_q used in dae_f.
    psi2d = Vq + Ra_n*Iq + Xdpp_sat*Id;  % E''q
    psi2q = Vd + Ra_n*Id - Xqpp_sat*Iq;  % E''d
    Eqp = psi2d + Id*(Xdp_n-Xdpp_n)/Satd0;
    Edp = psi2q - Iq*(Xqp_n-Xqpp_n)/Satq0;
    init.Efd(k) = Satd0*psi2d + Id*(Xd_n-Xdpp_n);
    init.Eqpi(k)=Eqp; init.Edpi(k)=Edp;
    init.Psipd(k)=psi2d; init.Psipq(k)=psi2q;   % store E''q, E''d

    x0((k-1)*6+1)=delta; x0((k-1)*6+2)=0;
    x0((k-1)*6+3)=Eqp; x0((k-1)*6+4)=Edp;
    x0((k-1)*6+5)=psi2d;   % E''q  (Kundur state 5)
    x0((k-1)*6+6)=psi2q;   % E''d  (Kundur state 6)

    init.state_names{(k-1)*6+1} = sprintf('\\delta_{%s}', M.units(k).gen_id);
    init.state_names{(k-1)*6+2} = sprintf('\\omega_{%s}', M.units(k).gen_id);
    init.state_names{(k-1)*6+3} = sprintf("E'_{q,%s}", M.units(k).gen_id);
    init.state_names{(k-1)*6+4} = sprintf("E'_{d,%s}", M.units(k).gen_id);
    init.state_names{(k-1)*6+5} = sprintf("E''_{q,%s}", M.units(k).gen_id);
    init.state_names{(k-1)*6+6} = sprintf("E''_{d,%s}", M.units(k).gen_id);
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
    line_r_scale = 1.0;
    if isfield(opts,'line_r_scale'); line_r_scale = opts.line_r_scale; end
    z = complex(line_r_scale*LD(l,3), LD(l,4)); y = 1/z;
    line_charging_scale = 1.0;
    if isfield(opts,'line_charging_scale'); line_charging_scale = opts.line_charging_scale; end
    Y(f,f)=Y(f,f)+y+1i*line_charging_scale*LD(l,5); Y(t,t)=Y(t,t)+y+1i*line_charging_scale*LD(l,5);
    Y(f,t)=Y(f,t)-y; Y(t,f)=Y(t,f)-y;
end
BD = case_data.bus_data;
for k = 1:size(BD,1)
    b = find(pf.external_bus_ids == BD(k,1), 1);
    bus_shunt_scale = 1.0;
    if isfield(opts,'bus_shunt_scale'); bus_shunt_scale = opts.bus_shunt_scale; end
    Y(b,b) = Y(b,b) + 1i*bus_shunt_scale*BD(k,10);
    Pload=BD(k,7); Qload=BD(k,8); Vmag=pf.bus_voltage(b);
    if Vmag>0
        switch lower(opts.load_model)
            case {'cz','cz_p_cz_q'}
                % Full constant-impedance load: P as conductance, Q as
                % susceptance.  Sign convention: load draws current, so the
                % equivalent shunt admittance is Y_load = conj(S_load)/|V|^2
                % = (P - jQ)/|V|^2.
                qload_z_scale = 1.0;
                if isfield(opts,'qload_z_scale'); qload_z_scale = opts.qload_z_scale; end
                if Pload~=0; Y(b,b) = Y(b,b) + Pload/(Vmag^2); end
                if Qload~=0; Y(b,b) = Y(b,b) - 1i*qload_z_scale*Qload/(Vmag^2); end
            case {'cc','cc_p_cc_q'}
                % Full constant-current: no shunt admittance; both P and Q
                % injected as current in dae_g.
            otherwise
                % Kundur Example a: const-current P (in dae_g), const-impedance Q.
                qload_z_scale = 1.0;
                if isfield(opts,'qload_z_scale'); qload_z_scale = opts.qload_z_scale; end
                if Qload~=0; Y(b,b) = Y(b,b) - 1i*qload_z_scale*Qload/(Vmag^2); end
        end
    end
end
Ynet = Y;
end

% =========================================================================
function init = refine_initial_state(init, M, Ynet, base, gamma)
%REFINE_INITIAL_STATE  Preserve the verified PF operating point exactly.
% The PF solver is the sole source of bus voltages and generator P/Q for
% initialization.  This routine only refreshes derived machine quantities;
% it must not alter x0, y0, Efd, or Tm through a second Newton/fsolve solve.
x = init.x0;
y = init.y0;
[Te0, Id0, Iq0, Vd0, Vq0] = te_at_op(x, y, init, M, Ynet, base, gamma, init.zb_scale);
init.Tm = Te0;
init.Id = Id0;
init.Iq = Iq0;
init.Vd = Vd0;
init.Vq = Vq0;
init.newton_iterations = 0;
f_final = dae_f(init.x0, init.y0, init, M, Ynet, base, gamma);
g_final = dae_g(init.x0, init.y0, init, M, Ynet, base, gamma, init.zb_scale);
init.newton_residual = norm([f_final; g_final]);
end

% =========================================================================
function [Te, Id_o, Iq_o, Vd_o, Vq_o] = te_at_op(x, y, init, M, Ynet, base, gamma, zb_scale)
R=M.reactances; ng=init.ng; nb=numel(y)/2;
V_bus=complex(zeros(nb,1),zeros(nb,1));
for b=1:nb; V_bus(b)=complex(y(2*b-1),y(2*b)); end
Te=zeros(ng,1); Id_o=zeros(ng,1); Iq_o=zeros(ng,1); Vd_o=zeros(ng,1); Vq_o=zeros(ng,1);
for k=1:ng
    [Id,Iq,Vd,Vq,~,~,Xdpp_sat,Xqpp_sat] = solve_stator( ...
        x,y,init,k,R,gamma,zb_scale);
    Eqpp = x((k-1)*6+5); Edpp = x((k-1)*6+6);
    % GENTPJ torque (MathWorks): E''d*Id + E''q*Iq - (X''d_sat - X''q_sat)*Id*Iq
    Te(k)=Edpp*Id + Eqpp*Iq - (Xdpp_sat-Xqpp_sat)*Id*Iq;
    Id_o(k)=Id; Iq_o(k)=Iq; Vd_o(k)=Vd; Vq_o(k)=Vq;
end
end

% =========================================================================
function [Id,Iq,Vd,Vq,Satd,Satq,Xdpp_sat,Xqpp_sat] = solve_stator(x,y,init,k,R,gamma,zb_scale)
%SOLVE_STATOR Solve the local nonlinear GENTPJ stator equations.
% The network voltage is an input and is never changed here.  Saturation
% depends on the air-gap flux, which depends on stator current; therefore
% the two current equations are solved to a fixed point and the identical
% solution is used by initialization, f, g, and torque.
nb = numel(y)/2;
V_bus = complex(zeros(nb,1),zeros(nb,1));
for b=1:nb; V_bus(b)=complex(y(2*b-1),y(2*b)); end
Vt = V_bus(init.bus_idx(k));
delta=x((k-1)*6+1);
Eqpp=x((k-1)*6+5); Edpp=x((k-1)*6+6);
Ra_n=R.Ra*zb_scale; Xl_n=R.Xl*zb_scale;
Xdpp_n=R.Xdpp*zb_scale; Xqpp_n=R.Xqpp*zb_scale;
[Vd,Vq]=stability.kundur_book_dq(Vt,delta);
rhs_d=Vd-Edpp; rhs_q=Vq-Eqpp;
% Unsaturated stator current is the starting point.
det0=Xdpp_n*Xqpp_n+Ra_n*Ra_n;
Id=(-Ra_n*rhs_d-Xqpp_n*rhs_q)/det0;
Iq=(Xdpp_n*rhs_d-Ra_n*rhs_q)/det0;
for it=1:100
    [Satd,Satq]=book_saturation_factors_stator(Vd,Vq,init,R,zb_scale,Id,Iq);
    Xdpp_sat=Xl_n+(Xdpp_n-Xl_n)/Satd;
    Xqpp_sat=Xl_n+(Xqpp_n-Xl_n)/Satq;
    det=Xdpp_sat*Xqpp_sat+Ra_n*Ra_n;
    Id_new=(-Ra_n*rhs_d-Xqpp_sat*rhs_q)/det;
    Iq_new=(Xdpp_sat*rhs_d-Ra_n*rhs_q)/det;
    if max(abs([Id_new-Id,Iq_new-Iq])) < 1e-13
        Id=Id_new; Iq=Iq_new;
        break;
    end
    % Damped fixed point is robust at the Kundur operating point and keeps
    % finite-difference Jacobians smooth.
    Id=0.5*(Id+Id_new); Iq=0.5*(Iq+Iq_new);
end
[Satd,Satq]=book_saturation_factors_stator(Vd,Vq,init,R,zb_scale,Id,Iq);
Xdpp_sat=Xl_n+(Xdpp_n-Xl_n)/Satd;
Xqpp_sat=Xl_n+(Xqpp_n-Xl_n)/Satq;
end

% =========================================================================
function [Jxx, Jxy, Jyx, Jyy] = build_dae_jacobian(init, M, Ynet, base, gamma, eps_p)
if nargin < 6 || isempty(eps_p); eps_p=1e-6; end
nx=numel(init.x0); ny=numel(init.y0);
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
%DAE_F  Differential equations dx/dt = f(x,y) using the GENTPJ
%6th-order realization (MathWorks GENTPJ block documentation).
% State vector per machine:
%   x_i = [ delta_i ; omega_i ; E'_q i ; E'_d i ; E''_q i ; E''_d i ]
% Saturation enters through total multipliers Satd and Satq.
% Reference: Kundur PSSC Example 12.6; MathWorks GENTPJ block equations.
w0=init.w0; R=M.reactances; TC=M.time_constants;
Sbase=base.S_base_MVA; Sm=M.base.S_MVA; ng=init.ng;
zb_scale=Sbase/Sm;
f=zeros(6*ng,1);
% Kundur coefficients (system pu)
Xd_n=R.Xd*zb_scale; Xdp_n=R.Xdp*zb_scale; Xdpp_n=R.Xdpp*zb_scale;
Xq_n=R.Xq*zb_scale; Xqp_n=R.Xqp*zb_scale; Xqpp_n=R.Xqpp*zb_scale;
c_d=(Xd_n-Xdp_n)/(Xdp_n-Xdpp_n);   % (Xd-X'd)/(X'd-X''d)
d_d=(Xd_n-Xdpp_n)/(Xdp_n-Xdpp_n);  % (Xd-X''d)/(X'd-X''d)
c_q=(Xq_n-Xqp_n)/(Xqp_n-Xqpp_n);   % (Xq-X'q)/(X'q-X''q)
d_q=(Xq_n-Xqpp_n)/(Xqp_n-Xqpp_n);  % (Xq-X''q)/(X'q-X''q)
for k=1:ng
    omega_dev=x((k-1)*6+2);
    Eqp=x((k-1)*6+3); Edp=x((k-1)*6+4);
    Eqpp=x((k-1)*6+5); Edpp=x((k-1)*6+6);
    [Id,Iq,~,~,Satd,Satq,Xdpp_sat,Xqpp_sat] = solve_stator( ...
        x,y,init,k,R,gamma,zb_scale);
    % Te = psi_d*Iq - psi_q*Id using the saturated stator fluxes.
    Te=Edpp*Id+Eqpp*Iq-(Xdpp_sat-Xqpp_sat)*Id*Iq;
    if isfield(init,'Tm') && ~isempty(init.Tm); Tm=init.Tm(k); else
        Tm=init.Vq(k)*init.Iq(k)+init.Vd(k)*init.Id(k); end
    H=init.H_sys(k); D=M.units(k).D*(Sm/Sbase);
    f((k-1)*6+1)=omega_dev*w0;
    f((k-1)*6+2)=(Tm-Te-D*omega_dev)/(2*H);
    % Satd/Satq already include the leading one: Satd=1+psi_I/psi_at.
    f((k-1)*6+3)=(init.Efd(k)+Satd*(Eqpp*c_d-Eqp*d_d))/TC.Tpd0;
    f((k-1)*6+4)=Satq*(Edpp*c_q-Edp*d_q)/TC.Tpq0;
    f((k-1)*6+5)=(Satd*(Eqp-Eqpp)-Id*(Xdp_n-Xdpp_n))/TC.Tppd0;
    f((k-1)*6+6)=(Satq*(Edp-Edpp)+Iq*(Xqp_n-Xqpp_n))/TC.Tppq0;
end
end

% =========================================================================
function [Satd,Satq] = book_saturation_factors_stator(Vd,Vq,init,R,zb_scale,Id,Iq)
%BOOK_SATURATION_FACTORS_STATOR Kundur Eq. (3.189) / GENTPJ multipliers.
% Kundur defines the saturation flux component
%   psi_I = Asat*exp(Bsat*(psi_at-PsiT1)),  psi_at > PsiT1.
% GENTPJ uses Satd=1+psi_I/psi_at.  Example 12.6 supplies no Kis
% parameter, so no armature-current term is added to the curve argument.
if nargin<7; Id=0; Iq=0; end
Xl_n=R.Xl*zb_scale; Ra_n=R.Ra*zb_scale;
psi_ad=Vq+Ra_n*Iq+Xl_n*Id;
psi_aq=Vd+Ra_n*Id-Xl_n*Iq;
psi_at=hypot(psi_ad,psi_aq);
Satd=1; Satq=1;
if ~(isfield(init,'opts') && isfield(init.opts,'use_saturation') && init.opts.use_saturation)
    return;
end
p=init.opts.sat_params;
sat_scale=1;
if isfield(init.opts,'sat_scale'); sat_scale=init.opts.sat_scale; end
if psi_at<=p.PsiT1
    sat_ratio=0;
else
    psi_I=p.Asat*exp(p.Bsat*(psi_at-p.PsiT1));
    sat_ratio=sat_scale*psi_I/psi_at;
end
Satd=1+sat_ratio;
if isfield(init.opts,'sat_q_axis') && ~init.opts.sat_q_axis
    Satq=1;
else
    Satq=1+(R.Xq/R.Xd)*sat_ratio;
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
case_data = cases.kundur_ex126_book_case();
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
                % Kundur Example 12.6: constant-current active load and
                % constant-impedance reactive load (already in Ynet).  No
                % frequency-sensitive load term is part of the benchmark.
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
    delta=x((k-1)*6+1);
    [Id,Iq]=solve_stator(x,y,init,k,R,gamma,zb_scale);
    Ig=stability.kundur_book_network_current(Id,Iq,delta);
    g(2*bidx-1)=real(Ig)-real(Inet(bidx));
    g(2*bidx)=imag(Ig)-imag(Inet(bidx));
end
end
