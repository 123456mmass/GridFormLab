function result = kundur_fault_simulation(varargin)
%KUNDUR_FAULT_SIMULATION Time-domain transient simulation of the Kundur
%two-area four-machine system subjected to a three-phase fault.
%
%   RESULT = kundur_fault_simulation() runs the default scenario:
%       3-phase solid fault at bus 8 (tie bus), cleared at t = 0.1 s
%       by removing one of the parallel 7-8 circuits (post-fault network).
%   Generators are modelled with the classical constant-voltage-behind-
%   transient-reactance model (E' constant, 2 states per machine).
%
%   RESULT = kundur_fault_simulation('bus', 8, 'tclear', 0.1, ...
%       'tmax', 5, 'dt', 1e-3) customises the scenario.
%
%   Outputs:
%     result.t           - time vector (s)
%     result.delta       - rotor angles of G1..G4 (rad), [Nt x 4]
%     result.omega       - rotor speed deviations (pu),     [Nt x 4]
%     result.Pgen        - generator active power (MW),     [Nt x 4]
%     result.Vbus        - bus voltage magnitudes (pu),     [Nt x nb]
%     result.Pgen_machine- per-generator electrical power (pu on 100 MVA)
%     result.bus_ids     - external bus ids
%     result.fault_bus   - faulted bus id
%     result.tclear      - fault clearing time (s)
%
%   Integration: implicit trapezoidal rule (PSAT-style), with a Newton
%   iteration per step to resolve the implicit electrical power.
%   Reference: F. Milano, "Power System Modelling and Scripting" (PSAT),
%   trapezoidal integration of the swing equations:
%       x_{n+1} = x_n + (dt/2)*(f(x_n) + f(x_{n+1}))
%   The state omega is speed deviation in pu. The swing equations follow the
%   PSAT convention:
%       d(delta)/dt = omega_s*omega
%       d(omega)/dt = (Pm - Pe - D*omega)/(2*H_system)
%   where H_system = H_machine*S_machine/S_system because Pm and Pe are on
%   the 100-MVA network base. Only MATLAB base built-ins are used (no toolbox).

% --- Parse options --------------------------------------------------------
bus_fault = 8;
tclear = 0.1;
tmax = 5;
dt = 1e-3;
tfault_start = 0.5;
temporary = true;
if nargin > 0 && isstruct(varargin{1})
    o = varargin{1};
    if isfield(o,'bus');          bus_fault    = o.bus;          end
    if isfield(o,'tclear');       tclear       = o.tclear;       end
    if isfield(o,'tmax');         tmax         = o.tmax;         end
    if isfield(o,'dt');            dt           = o.dt;           end
    if isfield(o,'tfault_start'); tfault_start = o.tfault_start; end
    if isfield(o,'temporary');    temporary    = o.temporary;    end
end

case_data = cases.case_kundur_two_area_classical();
opts = struct('plot_results', false, 'verbose', false, 'max_iter', 50, ...
    'tolerance', 1e-8, 'enforce_q_limits', false);
pf = pfsolver.powerflow_newton_raphson(case_data, opts);
if ~pf.converged
    error('kundur_fault_simulation:noPowerFlow', 'Power flow did not converge.');
end

M = case_data.machines;
nb = numel(pf.external_bus_ids);
bus_ids = pf.external_bus_ids;

% --- Pre-fault classical initialisation -----------------------------------
% Classical model: E' = V_t + (Ra + j X'd) I_t, delta = angle(E').
zb_scale = (M.base.V_kV^2/M.base.S_MVA) / (case_data.base_values.V_base_kV^2/case_data.base_values.S_base_MVA);
ng = numel(M.units);
delta0 = zeros(ng,1);
omega0 = zeros(ng,1);
Eprime = zeros(ng,1);   % |E'| (pu, network)
for k = 1:ng
    bidx = find(bus_ids == M.units(k).bus, 1);
    Vt = pf.bus_voltage(bidx) * exp(1i*deg2rad(pf.bus_angle_deg(bidx)));
    Sgen = pf.P_generation(bidx) + 1i*pf.Q_generation(bidx);
    It = conj(Sgen / Vt);
    R = M.reactances;
    Xdp_n = R.Xdp * zb_scale;
    Ra_n = R.Ra * zb_scale;
    Ep = Vt + (Ra_n + 1i*Xdp_n) * It;
    delta0(k) = angle(Ep);
    Eprime(k) = abs(Ep);
end
Pm = pf.P_generation(find(bus_ids==M.units(1).bus,1)) ... % mechanical power = pre-fault electrical power
       + 0; % keep as vector below
Pm_vec = zeros(ng,1);
for k = 1:ng
    bidx = find(bus_ids == M.units(k).bus, 1);
    Pm_vec(k) = pf.P_generation(bidx);   % network pu (100 MVA)
end
H_machine = zeros(ng,1);
H_sys = zeros(ng,1);
D_sys = zeros(ng,1);
for k = 1:ng
    H_machine(k) = M.units(k).H;                                      % seconds on 900-MVA machine base
    H_sys(k) = M.units(k).H * (M.base.S_MVA / case_data.base_values.S_base_MVA); % seconds on 100-MVA system base
    D_sys(k) = M.units(k).D * (M.base.S_MVA / case_data.base_values.S_base_MVA);
end
w0 = 2*pi*case_data.base_values.frequency_Hz;

% --- Build Ybus for pre-fault, during-fault, post-fault -------------------
Ypre  = build_ybus(case_data, bus_ids);
Yfault = apply_fault(Ypre, bus_ids, bus_fault);
if temporary
    Ypost = Ypre;     % temporary fault: network restored after clearing
else
    Ypost = remove_line(Ypre, case_data, bus_ids, bus_fault);
end

% --- Time integration: implicit trapezoidal rule (PSAT-style) -----------
%   x_{n+1} = x_n + (dt/2)*(f(x_n) + f(x_{n+1}))
%   where f depends on Pe, which depends on delta_{n+1} through the network.
%   Each step solves the nonlinear implicit equation by Newton iteration.
t_vec = 0:dt:tmax;
Nt = numel(t_vec);
delta_hist  = zeros(Nt, ng);
omega_hist  = zeros(Nt, ng);
Pgen_hist   = zeros(Nt, ng);
Vbus_hist   = zeros(Nt, nb);
Pe_hist     = zeros(Nt, ng);

state = [delta0; omega0];
newton_tol = 1e-8;
newton_maxit = 20;
for it = 1:Nt
    t = t_vec(it);
    if t < tfault_start
        Y = Ypre;
    elseif t < tfault_start + tclear
        Y = Yfault;
    else
        Y = Ypost;
    end
    [Pe, Vbus] = electrical_power(state, Eprime, M, bus_ids, Y, zb_scale, ng);
    delta_hist(it,:) = state(1:ng)';
    omega_hist(it,:) = state(ng+1:end)';
    Pgen_hist(it,:)  = Pe' * 100;   % pu -> MW (100 MVA base)
    Pe_hist(it,:)    = Pe';
    Vbus_hist(it,:)  = Vbus';
    if it < Nt
        % f(x_n)
        fn = derivatives(state, Pe, Pm_vec, H_sys, D_sys, w0, ng);
        % Newton iteration for x_{n+1}:  R(x) = x - x_n - (dt/2)*(fn + f(x)) = 0
        x_next = state + dt*fn;   % predictor (explicit Euler)
        for nit = 1:newton_maxit
            [Pe_next,~] = electrical_power(x_next, Eprime, M, bus_ids, Y, zb_scale, ng);
            f_next = derivatives(x_next, Pe_next, Pm_vec, H_sys, D_sys, w0, ng);
            R = x_next - state - 0.5*dt*(fn + f_next);
            if norm(R, inf) < newton_tol
                break;
            end
            % Jacobian of R w.r.t. x_next:  dR/dx = I - 0.5*dt*df/dx.
            % df/dx is computed by finite differences (only Pe depends on x).
            nx = 2*ng; eps_j = 1e-6;
            J = eye(nx);
            for j = 1:nx
                xp = x_next; xp(j) = xp(j) + eps_j;
                xm = x_next; xm(j) = xm(j) - eps_j;
                [Pep,~] = electrical_power(xp, Eprime, M, bus_ids, Y, zb_scale, ng);
                [Pem,~] = electrical_power(xm, Eprime, M, bus_ids, Y, zb_scale, ng);
                fp = derivatives(xp, Pep, Pm_vec, H_sys, D_sys, w0, ng);
                fm = derivatives(xm, Pem, Pm_vec, H_sys, D_sys, w0, ng);
                J(:,j) = J(:,j) - 0.5*dt*(fp - fm)/(2*eps_j);
            end
            dx = J \ (-R);
            x_next = x_next + dx;
        end
        state = x_next;
    end
end

result = struct();
result.t = t_vec;
result.delta = delta_hist;
result.omega = omega_hist;
result.Pgen = Pgen_hist;
result.Pe_pu = Pe_hist;
result.Vbus = Vbus_hist;
result.bus_ids = bus_ids;
result.fault_bus = bus_fault;
result.tclear = tclear;
result.tfault_start = tfault_start;
result.Eprime = Eprime;
result.delta0 = delta0;
result.H_machine = H_machine;
result.H_sys = H_sys;
result.D_sys = D_sys;
result.Pm = Pm_vec;
result.integration_method = 'implicit trapezoidal (PSAT-style)';
result.temporary = temporary;
result.Ypre = Ypre;
result.Yfault = Yfault;
result.Ypost = Ypost;
end

% =========================================================================
function dy = derivatives(state, Pe, Pm, H, D, w0, ng)
delta = state(1:ng); %#ok<NASGU>
omega = state(ng+1:end);
dy = zeros(2*ng,1);
dy(1:ng)     = omega * w0;
dy(ng+1:end) = (Pm - Pe - D.*omega) ./ (2*H);
end

% =========================================================================
function [Pe, Vbus] = electrical_power(state, Eprime, M, bus_ids, Y, zb_scale, ng)
% Solve the network with generators as constant E' behind X'd and return
% the electrical power of each generator and the bus voltage magnitudes.
nb = numel(bus_ids);
R = M.reactances;
% Build augmented Y with internal generator nodes.
% Internal node i connects to terminal bus through Ra + j X'd (network pu).
na = nb + ng;
Ya = complex(zeros(na,na), zeros(na,na));
Ya(1:nb, 1:nb) = Y;
for k = 1:ng
    bidx = find(bus_ids == M.units(k).bus, 1);
    inode = nb + k;
    Xdp_n = R.Xdp * zb_scale;
    Ra_n = R.Ra * zb_scale;
    z = complex(Ra_n, Xdp_n);
    y = 1/z;
    Ya(bidx, bidx)   = Ya(bidx, bidx) + y;
    Ya(inode, inode) = Ya(inode, inode) + y;
    Ya(bidx, inode)  = Ya(bidx, inode) - y;
    Ya(inode, bidx)  = Ya(inode, bidx) - y;
end
% Known internal EMFs as current injections: I = E'/(Ra+jX'd) at internal node.
Iinj = complex(zeros(na,1), zeros(na,1));
V = complex(zeros(na,1));
for k = 1:ng
    inode = nb + k;
    delta = state(k);
    V(inode) = Eprime(k) * exp(1i*delta);
    Xdp_n = R.Xdp * zb_scale;
    Ra_n = R.Ra * zb_scale;
    z = complex(Ra_n, Xdp_n);
    Iinj(inode) = V(inode) / z;
end
% Partition: unknown terminal bus voltages V_t (nb), known internal V (ng).
A = Ya(1:nb, 1:nb);
bvec = Iinj(1:nb) - Ya(1:nb, nb+1:na) * V(nb+1:na);
Vt = A \ bvec;
Vbus = abs(Vt);
% Generator currents and powers
Pe = zeros(ng,1);
for k = 1:ng
    inode = nb + k;
    bidx = find(bus_ids == M.units(k).bus, 1);
    Ig = (V(inode) - Vt(bidx)) / complex(R.Ra*zb_scale, R.Xdp*zb_scale);
    Pe(k) = real(Vt(bidx) * conj(Ig));
end
end

% =========================================================================
function Y = build_ybus(case_data, bus_ids)
%BUILD_YBUS Build the network admittance matrix with constant-impedance
%load equivalents evaluated at the converged power-flow voltages.
cd_opts = struct('plot_results', false, 'verbose', false, 'max_iter', 50, ...
    'tolerance', 1e-8, 'enforce_q_limits', false);
pf = pfsolver.powerflow_newton_raphson(case_data, cd_opts);
nb = numel(bus_ids);
Y = complex(zeros(nb,nb), zeros(nb,nb));
LD = case_data.line_data;
for l = 1:size(LD,1)
    f = find(bus_ids == LD(l,1), 1);
    t = find(bus_ids == LD(l,2), 1);
    z = complex(LD(l,3), LD(l,4));
    y = 1/z;
    Y(f,f) = Y(f,f) + y + 1i*LD(l,5);
    Y(t,t) = Y(t,t) + y + 1i*LD(l,5);
    Y(f,t) = Y(f,t) - y;
    Y(t,f) = Y(t,f) - y;
end
% Shunt capacitors and constant-impedance loads (using power-flow Vmag)
BD = case_data.bus_data;
for k = 1:size(BD,1)
    b = find(bus_ids == BD(k,1), 1);
    Y(b,b) = Y(b,b) + 1i*BD(k,10);
    Pload = BD(k,7); Qload = BD(k,8);
    Vmag = pf.bus_voltage(b);
    if Vmag > 0 && (Pload ~= 0 || Qload ~= 0)
        Y(b,b) = Y(b,b) + (Pload - 1i*Qload)/(Vmag^2);
    end
end
end

% =========================================================================
function Yf = apply_fault(Y, bus_ids, bus_fault)
% Solid 3-phase fault: zero voltage at the fault bus => remove bus from
% network by zeroing its row/column and putting 1 on the diagonal so the
% voltage is forced to 0 in the linear solve.
Yf = Y;
b = find(bus_ids == bus_fault, 1);
Yf(b,:) = 0;
Yf(:,b) = 0;
Yf(b,b) = 1;
end

% =========================================================================
function Yp = remove_line(Y, case_data, bus_ids, bus_fault)
% Post-fault: remove one of the parallel tie circuits adjacent to the
% faulted bus to mimic a cleared fault. If bus_fault == 8, drop one
% 7-8 and one 8-9 circuit (i.e. one of the two parallel tie sections).
Yp = Y;
LD = case_data.line_data;
to_drop = [];
if bus_fault == 8
    % drop first 7-8 and first 8-9 occurrences
    found78 = false; found89 = false;
    for l = 1:size(LD,1)
        if ~found78 && ((LD(l,1)==7 && LD(l,2)==8) || (LD(l,1)==8 && LD(l,2)==7))
            to_drop(end+1) = l; found78 = true;
        elseif ~found89 && ((LD(l,1)==8 && LD(l,2)==9) || (LD(l,1)==9 && LD(l,2)==8))
            to_drop(end+1) = l; found89 = true;
        end
    end
end
for ii = 1:numel(to_drop)
    l = to_drop(ii);
    f = find(bus_ids == LD(l,1), 1);
    t = find(bus_ids == LD(l,2), 1);
    z = complex(LD(l,3), LD(l,4));
    y = 1/z;
    Yp(f,f) = Yp(f,f) - y - 1i*LD(l,5);
    Yp(t,t) = Yp(t,t) - y - 1i*LD(l,5);
    Yp(f,t) = Yp(f,t) + y;
    Yp(t,f) = Yp(t,f) + y;
end
end
