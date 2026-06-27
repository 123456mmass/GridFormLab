function result = kundur_ex126_sixth_order_ssa(varargin)
%KUNDUR_EX126_SIXTH_ORDER_SSA Small-signal stability of the Kundur 4-machine
%two-area system using a genuine 6th-order synchronous-machine model.
%
%   RESULT = kundur_ex126_sixth_order_ssa() runs on the in-house power-flow
%   solution of +cases/case_kundur_two_area_classical and assembles a 24-state
%   linearized model (6 states x 4 generators). The reduced state matrix is
%   obtained by eliminating the network algebraic variables with a Schur
%   complement. Eigenvalues, mode shapes, and a comparison against Kundur
%   Table E12.3 are returned.
%
%   RESULT = kundur_ex126_sixth_order_ssa('pf', PF) uses a pre-computed
%   power-flow result PF. Otherwise the function runs the in-house
%   Newton-Raphson solver.
%
%   Only MATLAB base built-ins are used. No power-system toolbox is called.
%
%   State vector per generator i (manual excitation, E_fd constant):
%       x_i = [ delta_i ; omega_i ; E'qi ; E'di ; E''qi ; E''di ]
%
%   Reference: Kundur, Power System Stability and Control,
%   Chapter 12, Example 12.6 (Table E12.3 manual excitation).

pf = [];
if nargin >= 2 && strcmpi(varargin{1}, 'pf')
    pf = varargin{2};
end

% --- 1. Power-flow solution ------------------------------------------------
if isempty(pf)
    case_data = cases.case_kundur_two_area_classical();
    opts = struct('plot_results', false, 'verbose', false, ...
        'max_iter', 50, 'tolerance', 1e-8, 'enforce_q_limits', false);
    pf = pfsolver.powerflow_newton_raphson(case_data, opts);
end
case_data = cases.case_kundur_two_area_classical();
M = case_data.machines;

if ~pf.converged
    error('kundur_ex126_sixth_order_ssa:noConvergence', ...
        'Power-flow did not converge; cannot build 6th-order model.');
end

% --- 2. Initial conditions of each generator -------------------------------
% Terminal phasors in the network (system) reference frame.
[init, Ynet] = initialise_generators(pf, case_data, M);

% --- 3. Build the DAE and linearise ---------------------------------------
[Jxx, Jxy, Jyx, Jyy] = build_dae_jacobian(init, M, Ynet, case_data.base_values);

% Eliminate algebraic variables y:  dx = (Jxx - Jxy*Jyy\Jyx) x
Ared = Jxx - Jxy * (Jyy \ Jyx);

% --- 4. Eigenvalues and mode shapes ---------------------------------------
lambda = eig(Ared);
[~, D] = eig(Ared);
% participation / right eigenvector magnitudes (kept for future GUI use)
mode_shapes = D;

result = struct();
result.Ared = Ared;
result.eigenvalues = lambda;
result.state_names = init.state_names;
result.algebraic_names = init.algebraic_names;
result.init = init;
result.mode_shapes = mode_shapes;
result.frequency_Hz = abs(imag(lambda)) / (2*pi);
result.damping_ratio = -real(lambda) ./ (abs(lambda) + eps);
result.stable = all(real(lambda) < 0);

% (debug) residual magnitudes at the operating point — exposed for
% verification that f(x0,y0) and g(x0,y0) are zero.
result.debug_residual_f = dae_f(init.x0, init.y0, init, M, Ynet, case_data.base_values);
result.debug_residual_g = dae_g(init.x0, init.y0, init, M, Ynet, case_data.base_values);

% Compare to the textbook benchmark (manual excitation, Table E12.3).
ref = stability.kundur_ex126_classical_analysis();
result.reference = ref;
result.reference_summary = build_reference_summary(lambda, ref);
end

% =========================================================================
function [init, Ynet] = initialise_generators(pf, case_data, M)
%INITIALISE_GENERATORS Compute steady-state states of each 6th-order machine
%   from the power-flow terminal conditions, and assemble the augmented
%   network admittance matrix including the load equivalents.
w0 = 2*pi*case_data.base_values.frequency_Hz;
Sbase = case_data.base_values.S_base_MVA;
Sm = M.base.S_MVA;
zb = (case_data.base_values.V_base_kV)^2 / Sbase;   % network base impedance
zgen = (M.base.V_kV)^2 / Sm;                          % machine base impedance
% machine pu -> network pu scaling
zb_scale = zgen / zb;

ng = numel(M.units);
states_per_gen = 6;
init.state_names = cell(ng*states_per_gen, 1);
x0 = zeros(ng*states_per_gen, 1);

% Generator internal-node data
init.delta = zeros(ng,1);
init.Efd = zeros(ng,1);
init.Vt = zeros(ng,1); init.Vt_ang = zeros(ng,1);
init.It = zeros(ng,1); init.It_ang = zeros(ng,1);
init.bus_idx = zeros(ng,1);
init.Eqpi = zeros(ng,1); init.Edpi = zeros(ng,1);
init.Eqppi = zeros(ng,1); init.Edppi = zeros(ng,1);
init.Id = zeros(ng,1); init.Iq = zeros(ng,1);
init.Vd = zeros(ng,1); init.Vq = zeros(ng,1);

for k = 1:ng
    bus_id = M.units(k).bus;
    bidx = find(pf.external_bus_ids == bus_id, 1);
    init.bus_idx(k) = bidx;
    Vmag = pf.bus_voltage(bidx);
    Vang = deg2rad(pf.bus_angle_deg(bidx));
    Vt = Vmag * exp(1i*Vang);                  % network pu
    % Generator terminal power (network pu on Sbase) and current (network pu)
    Sgen = pf.P_generation(bidx) + 1i*pf.Q_generation(bidx);
    It_net = conj(Sgen / Vt);                 % network pu current
    init.Vt(k) = Vmag; init.Vt_ang(k) = Vang;
    init.It(k) = abs(It_net); init.It_ang(k) = angle(It_net);

    R = M.reactances;
    % Initial rotor angle: align q-axis so that the steady-state internal
    % voltage E_q = V_q + R_a I_q + X_d I_d lies behind X_d. We solve the
    % classical "voltage behind synchronous reactance" angle.
    R = struct();
    R = M.reactances;
    % steady-state: E = Vt + (Ra + j Xd) It  (using Xd for q-axis steady state)
    % It and Vt are on the network pu base here, so reactances must be on
    % the network pu base too:  X_net = X_machine * zb_scale.
    Xd_n  = R.Xd   * zb_scale;
    Xdp_n = R.Xdp  * zb_scale;
    Xdpp_n= R.Xdpp * zb_scale;
    Xq_n  = R.Xq   * zb_scale;
    Xqp_n = R.Xqp  * zb_scale;
    Xqpp_n= R.Xqpp * zb_scale;
    Ra_n  = R.Ra   * zb_scale;

    Eqd_ss = Vt + (Ra_n + 1i*Xd_n) * It_net;
    delta = angle(Eqd_ss);
    init.delta(k) = delta;

    % Currents in the dq frame (network pu). Id, Iq follow the machine
    % convention (current OUT of the machine into the network). For a
    % generator, conj(S/V) is already the current injected into the bus
    % (= current out of the machine), so no sign flip is needed.
    Id =  sin(delta)*real(It_net) - cos(delta)*imag(It_net);
    Iq =  cos(delta)*real(It_net) + sin(delta)*imag(It_net);
    Vd =  sin(delta)*real(Vt) - cos(delta)*imag(Vt);
    Vq =  cos(delta)*real(Vt) + sin(delta)*imag(Vt);
    init.Id(k) = Id; init.Iq(k) = Iq;
    init.Vd(k) = Vd; init.Vq(k) = Vq;

    % Steady-state internal field voltage (constant for manual excitation)
    Eq  = Vq - Ra_n*Iq - Xd_n *Id;   init.Efd(k) = Eq;
    % Transient voltages (current out of machine convention)
    Eqp = Vq - Ra_n*Iq - Xdp_n*Id;
    Edp = Vd - Ra_n*Id + Xqp_n*Iq;
    % Subtransient voltages
    Eqpp = Vq - Ra_n*Iq - Xdpp_n*Id;
    Edpp = Vd - Ra_n*Id + Xqpp_n*Iq;
    init.Eqpi(k) = Eqp; init.Edpi(k) = Edp;
    init.Eqppi(k) = Eqpp; init.Edppi(k) = Edpp;

    x0((k-1)*6+1) = delta;
    x0((k-1)*6+2) = 0;        % omega deviation = 0 at steady state
    x0((k-1)*6+3) = Eqp;
    x0((k-1)*6+4) = Edp;
    x0((k-1)*6+5) = Eqpp;
    x0((k-1)*6+6) = Edpp;

    init.state_names{(k-1)*6+1} = sprintf('\\delta_{%s}', M.units(k).gen_id);
    init.state_names{(k-1)*6+2} = sprintf('\\omega_{%s}', M.units(k).gen_id);
    init.state_names{(k-1)*6+3} = sprintf("E'_{q,%s}", M.units(k).gen_id);
    init.state_names{(k-1)*6+4} = sprintf("E'_{d,%s}", M.units(k).gen_id);
    init.state_names{(k-1)*6+5} = sprintf("E''_{q,%s}", M.units(k).gen_id);
    init.state_names{(k-1)*6+6} = sprintf("E''_{d,%s}", M.units(k).gen_id);
end
init.x0 = x0;
init.ng = ng;
init.w0 = w0;
% Inertia constants on the system (100 MVA) base for the swing equation.
init.H_sys = zeros(ng,1);
for k=1:ng; init.H_sys(k) = M.units(k).H * (Sm/Sbase); end

% Network admittance matrix including load equivalents.
Ynet = build_network_admittance(pf, case_data, M, zb_scale);

% Algebraic variables = (Re, Im) of every bus voltage (kept consistent with
% the power-flow solution).
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
function Ynet = build_network_admittance(pf, case_data, M, zb_scale)
%BUILD_NETWORK_ADMITTANCE Build the complex bus admittance matrix on the
%network base, including constant-impedance load equivalents.
nb = numel(pf.external_bus_ids);
Y = complex(zeros(nb, nb), zeros(nb, nb));

% Build base admittance from line data
LD = case_data.line_data;
for l = 1:size(LD, 1)
    f = find(pf.external_bus_ids == LD(l,1), 1);
    t = find(pf.external_bus_ids == LD(l,2), 1);
    r = LD(l,3); x = LD(l,4); bhalf = LD(l,5);
    z = complex(r, x);
    y = 1/z;
    Y(f,f) = Y(f,f) + y + 1i*bhalf;
    Y(t,t) = Y(t,t) + y + 1i*bhalf;
    Y(f,t) = Y(f,t) - y;
    Y(t,f) = Y(t,f) - y;
end

% Add shunt capacitors and load equivalents at load buses
BD = case_data.bus_data;
for k = 1:size(BD,1)
    b = find(pf.external_bus_ids == BD(k,1), 1);
    Bsh = BD(k,10);
    Y(b,b) = Y(b,b) + 1i*Bsh;
    Pload = BD(k,7); Qload = BD(k,8);
    Vmag = pf.bus_voltage(b);
    if Vmag > 0 && (Pload ~= 0 || Qload ~= 0)
        Yload = (Pload - 1i*Qload) / (Vmag^2);
        Y(b,b) = Y(b,b) + Yload;
    end
end

% Generator stator admittance is NOT added to Ynet here: the generator
% current injections are computed explicitly in dae_g from the machine
% subtransient equations, so adding the shunt admittance would double-count.

Ynet = Y;
end

% =========================================================================
function [Jxx, Jxy, Jyx, Jyy] = build_dae_jacobian(init, M, Ynet, base)
%BUILD_DAE_JACOBIAN Numerically linearise the 6th-order DAE about the
%operating point.  dx = f(x,y), 0 = g(x,y).
%
%   State  x : [delta_i, omega_i, E'q_i, E'd_i, E''q_i, E''d_i] (6*ng x 1)
%   Algeb. y : [Re(V_b); Im(V_b)] for every network bus (2*nb x 1)
%
%   The Schur-complement reduction gives  A = Jxx - Jxy*(Jyy\Jyx).
eps_pert = 1e-6;
ng = init.ng;
nx = 6*ng;
nb = (numel(init.y0))/2;
ny = 2*nb;

x0 = init.x0;
y0 = init.y0;

% Jacobian blocks via central differences
Jxx = zeros(nx, nx);
Jxy = zeros(nx, ny);
Jyx = zeros(ny, nx);
Jyy = zeros(ny, ny);

fx0 = dae_f(x0, y0, init, M, Ynet, base);
gx0 = dae_g(x0, y0, init, M, Ynet, base);

for i = 1:nx
    xp = x0; xp(i) = xp(i) + eps_pert;
    xm = x0; xm(i) = xm(i) - eps_pert;
    fp = dae_f(xp, y0, init, M, Ynet, base);
    fm = dae_f(xm, y0, init, M, Ynet, base);
    gp = dae_g(xp, y0, init, M, Ynet, base);
    gm = dae_g(xm, y0, init, M, Ynet, base);
    Jxx(:,i) = (fp - fm) / (2*eps_pert);
    Jyx(:,i) = (gp - gm) / (2*eps_pert);
end
for j = 1:ny
    yp = y0; yp(j) = yp(j) + eps_pert;
    ym = y0; ym(j) = ym(j) - eps_pert;
    fp = dae_f(x0, yp, init, M, Ynet, base);
    fm = dae_f(x0, ym, init, M, Ynet, base);
    gp = dae_g(x0, yp, init, M, Ynet, base);
    gm = dae_g(x0, ym, init, M, Ynet, base);
    Jxy(:,j) = (fp - fm) / (2*eps_pert);
    Jyy(:,j) = (gp - gm) / (2*eps_pert);
end
end

% =========================================================================
function f = dae_f(x, y, init, M, Ynet, base)
%DAE_F Differential equations of the 6th-order model.
%
%   Per generator (network pu, time in seconds):
%     d delta   = omega_dev * w0
%     d omega   = (1/2H) (Tm - Te - D*omega_dev)
%     d E'q     = (1/T'd0) (Efd - E'q - (Xd-X'd) Id)
%     d E'd     = (1/T'q0) (-E'd + (Xq-X'q) Iq)
%     d E''q    = (1/T''d0)(E'q - E''q - (X'd-X''d) Id)
%     d E''d    = (1/T''q0)(E'd - E''d + (X'q-X''q) Iq)
%
%   Stator currents are solved from the stator algebraic equations so that
%   they are consistent with the present Vt, E'q, E'd, E''q, E''d.
w0 = init.w0;
R = M.reactances;
TC = M.time_constants;
Sbase = base.S_base_MVA;
Sm = M.base.S_MVA;
ng = init.ng;
zb_scale_k = (M.base.V_kV^2/Sm) / (base.V_base_kV^2/Sbase);
f = zeros(6*ng, 1);

% Recover bus voltages from algebraic variables (network pu on Sbase)
nb = numel(init.y0)/2;
V_bus = complex(zeros(nb,1), zeros(nb,1));
for b = 1:nb
    V_bus(b) = complex(y(2*b-1), y(2*b));
end

for k = 1:ng
    bidx = init.bus_idx(k);
    Vt = V_bus(bidx);
    delta = x((k-1)*6+1);
    omega_dev = x((k-1)*6+2);
    Eqp = x((k-1)*6+3);
    Edp = x((k-1)*6+4);
    Eqpp = x((k-1)*6+5);
    Edpp = x((k-1)*6+6);
    % Reactances in network pu (machine pu * zb_scale)
    Xd_n   = R.Xd   * zb_scale_k;
    Xdp_n  = R.Xdp  * zb_scale_k;
    Xdpp_n = R.Xdpp * zb_scale_k;
    Xq_n   = R.Xq   * zb_scale_k;
    Xqp_n  = R.Xqp  * zb_scale_k;
    Xqpp_n = R.Xqpp * zb_scale_k;
    Ra_n   = R.Ra   * zb_scale_k;
    % dq decomposition of terminal voltage (network pu)
    Vd =  sin(delta)*real(Vt) - cos(delta)*imag(Vt);
    Vq =  cos(delta)*real(Vt) + sin(delta)*imag(Vt);
    % Stator algebraic equations (full form, with Ra, network pu):
    %   Vd = Edpp + Ra Id - Xqpp Iq
    %   Vq = Eqpp + Ra Iq + Xdpp Id
    % Solve [Ra -Xqpp; Xdpp Ra] [Id; Iq] = [Vd-Edpp; Vq-Eqpp]
    det = Xdpp_n*Xqpp_n + Ra_n*Ra_n;
    Id = ( Ra_n*(Vd - Edpp) + Xqpp_n*(Vq - Eqpp) ) / det;
    Iq = ( -Xdpp_n*(Vd - Edpp) + Ra_n*(Vq - Eqpp) ) / det;
    % Electrical torque (network pu); V and I on the same pu scale here.
    Te = Vq*Iq + Vd*Id;
    % Mechanical torque equals steady-state electrical torque.
    Tm = init.Vq(k)*init.Iq(k) + init.Vd(k)*init.Id(k);
    H = init.H_sys(k);
    D = M.units(k).D * (Sm / Sbase);
    f((k-1)*6+1) = omega_dev * w0;
    f((k-1)*6+2) = (Tm - Te - D*omega_dev) / (2*H);
    f((k-1)*6+3) = (init.Efd(k) - Eqp - (Xd_n - Xdp_n)*Id) / TC.Tpd0;
    f((k-1)*6+4) = (-Edp + (Xq_n - Xqp_n)*Iq) / TC.Tpq0;
    f((k-1)*6+5) = (Eqp - Eqpp - (Xdp_n - Xdpp_n)*Id) / TC.Tppd0;
    f((k-1)*6+6) = (Edp - Edpp + (Xqp_n - Xqpp_n)*Iq) / TC.Tppq0;
end
end

% =========================================================================
function g = dae_g(x, y, init, M, Ynet, base)
%DAE_G Algebraic network equations:  I_inj - Ybus*V = 0 for every bus.
%   At generator buses the injection equals the machine stator current in
%   the network frame (consistent with dae_f). At load buses the injection
%   is already embedded in Ynet (constant-impedance loads), so the residual
%   is simply  Ynet*V - 0.
Sbase = base.S_base_MVA;
Sm = M.base.S_MVA;
ng = init.ng;
nb = numel(init.y0)/2;

V_bus = complex(zeros(nb,1), zeros(nb,1));
for b = 1:nb
    V_bus(b) = complex(y(2*b-1), y(2*b));
end

% Network current injections from Ybus (already includes loads and shunts
% as shunt admittances; generator stator admittance is NOT in Ynet here so
% we add it explicitly as the Norton current source).
Inet = Ynet * V_bus;

R = M.reactances;
zb_scale = (M.base.V_kV^2/Sm) / (base.V_base_kV^2/Sbase);

g = zeros(2*nb, 1);
% At non-generator buses the residual is 0 - Inet = -Inet (no injection).
for b = 1:nb
    g(2*b-1) = -real(Inet(b));
    g(2*b  ) = -imag(Inet(b));
end

for k = 1:ng
    bidx = init.bus_idx(k);
    Vt = V_bus(bidx);
    delta = x((k-1)*6+1);
    Eqpp = x((k-1)*6+5);
    Edpp = x((k-1)*6+6);
    % Reactances in network pu
    Xdpp_n = R.Xdpp * zb_scale;
    Xqpp_n = R.Xqpp * zb_scale;
    Ra_n   = R.Ra   * zb_scale;
    % dq stator voltages
    Vd =  sin(delta)*real(Vt) - cos(delta)*imag(Vt);
    Vq =  cos(delta)*real(Vt) + sin(delta)*imag(Vt);
    % Stator algebraic solution (network pu)
    det = Xdpp_n*Xqpp_n + Ra_n*Ra_n;
    Id = ( Ra_n*(Vd - Edpp) + Xqpp_n*(Vq - Eqpp) ) / det;
    Iq = ( -Xdpp_n*(Vd - Edpp) + Ra_n*(Vq - Eqpp) ) / det;
    % Id, Iq are machine currents OUT of the machine (into the network),
    % i.e. the network injection directly (no sign flip).
    Ire =  sin(delta)*Id + cos(delta)*Iq;
    Iim = -cos(delta)*Id + sin(delta)*Iq;
    Ig_net = complex(Ire, Iim);
    % Residual: generator injection into bus minus network outflow.
    g(2*bidx-1) =  real(Ig_net) - real(Inet(bidx));
    g(2*bidx  ) =  imag(Ig_net) - imag(Inet(bidx));
end
end

% =========================================================================
function [g, Iinj_out, Id_out, Iq_out] = dae_g_diag(x, y, init, M, Ynet, base)
%DAE_G_DIAG Diagnostic variant of dae_g that also returns the generator
%bus current injections and the per-machine (Id, Iq) currents.
Sbase = base.S_base_MVA;
Sm = M.base.S_MVA;
ng = init.ng;
nb = numel(init.y0)/2;

V_bus = complex(zeros(nb,1), zeros(nb,1));
for b = 1:nb
    V_bus(b) = complex(y(2*b-1), y(2*b));
end

Iinj_out = Ynet * V_bus;
R = M.reactances;
zb_scale = (M.base.V_kV^2/Sm) / (base.V_base_kV^2/Sbase);
Id_out = zeros(ng,1); Iq_out = zeros(ng,1);

for k = 1:ng
    bidx = init.bus_idx(k);
    Vt = V_bus(bidx);
    delta = x((k-1)*6+1);
    Eqpp = x((k-1)*6+5);
    Edpp = x((k-1)*6+6);
    Xdpp_n = R.Xdpp * zb_scale;
    Xqpp_n = R.Xqpp * zb_scale;
    Ra_n   = R.Ra   * zb_scale;
    Vd =  sin(delta)*real(Vt) - cos(delta)*imag(Vt);
    Vq =  cos(delta)*real(Vt) + sin(delta)*imag(Vt);
    det = Xdpp_n*Xqpp_n + Ra_n*Ra_n;
    Id = ( Ra_n*(Vd - Edpp) + Xqpp_n*(Vq - Eqpp) ) / det;
    Iq = ( -Xdpp_n*(Vd - Edpp) + Ra_n*(Vq - Eqpp) ) / det;
    Id_out(k) = Id; Iq_out(k) = Iq;
    Ire =  sin(delta)*Id + cos(delta)*Iq;
    Iim = -cos(delta)*Id + sin(delta)*Iq;
    Iinj_out(bidx) = complex(Ire, Iim);
end
g = zeros(2*nb, 1);
for b = 1:nb
    g(2*b-1) = real(Iinj_out(b));
    g(2*b  ) = imag(Iinj_out(b));
end
end

% =========================================================================
function s = build_reference_summary(lambda, ref)
%BUILD_REFERENCE_SUMMARY Pair computed eigenvalues with the closest textbook
%eigenvalue from Kundur Table E12.3 and return a comparison table.
T = ref.full_table;
book = struct('mode', {}, 'real', {}, 'imag', {});
for k = 1:size(T,1)
    r = sscanf(T{k,2}, '%f');
    if isempty(r); r = NaN; end
    im = NaN;
    if ~strcmp(T{k,3}, '-')
        im = sscanf(strrep(T{k,3}, '+/-',''), '%f');
        if isempty(im); im = NaN; end
    end
    book(end+1).mode = T{k,1};
    book(end).real = r(1);
    book(end).imag = im;
end

% Build computed list: complex pairs appear once in upper half-plane
lam_sorted = sortrows([real(lambda), imag(lambda)], [1 -2]);
% Pair each book eigenvalue with nearest computed eigenvalue (upper half)
s = struct('mode', {}, 'computed', {}, 'book_real', {}, 'book_imag', {});
used = false(size(lam_sorted,1), 1);
for k = 1:numel(book)
    br = book(k).real; bi = book(k).imag;
    best = inf; best_idx = 0;
    for j = 1:size(lam_sorted,1)
        if used(j); continue; end
        if isnan(bi)
            d = abs(lam_sorted(j,1) - br) + abs(lam_sorted(j,2));
        else
            d = hypot(lam_sorted(j,1) - br, lam_sorted(j,2) - abs(bi));
        end
        if d < best
            best = d; best_idx = j;
        end
    end
    if best_idx > 0
        used(best_idx) = true;
        s(end+1).mode = book(k).mode;
        s(end).computed = complex(lam_sorted(best_idx,1), lam_sorted(best_idx,2));
        s(end).book_real = br;
        s(end).book_imag = bi;
    else
        s(end+1).mode = book(k).mode;
        s(end).computed = NaN;
        s(end).book_real = br;
        s(end).book_imag = bi;
    end
end
end
