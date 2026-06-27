function result = kundur_ex126_sauer_pai_ssa(varargin)
%KUNDUR_EX126_SAUER_PAI_SSA Small-signal stability of the Kundur 4-machine
%two-area system using the full 6th-order Sauer-Pai synchronous-machine model.
%
%   RESULT = kundur_ex126_sauer_pai_ssa() runs the in-house Newton-Raphson
%   power flow on +cases/case_kundur_two_area_classical, then assembles a
%   24-state linearised model (6 states x 4 generators). The reduced state
%   matrix is obtained by Schur complement; eigenvalues are compared with
%   Kundur Table E12.3.
%
%   State vector per machine i (manual excitation, E_fd constant):
%       x_i = [ delta_i ; omega_i ; E'qi ; E'di ; psi''di ; psi''qi ]
%
%   Reference: Sauer & Pai, "Power System Dynamics and Stability", 2006.
%   The implementation uses gamma-coupled subtransient internal voltages:
%       E''q = gamma_d1 E'q + (1-gamma_d1) psi''d
%       E''d = gamma_q1 E'd + (1-gamma_q1) psi''q
%   with gamma_d1 = (X''d - Xl)/(X'd - Xl), gamma_q1 = (X''q - Xl)/(X'q - Xl),
%   and stator equations in generator-current convention:
%       Vd = E''d - Ra Id + X''q Iq
%       Vq = E''q - Ra Iq - X''d Id

pf = [];
if nargin >= 2 && strcmpi(varargin{1}, 'pf')
    pf = varargin{2};
end

if isempty(pf)
    case_data = cases.case_kundur_two_area_classical();
    opts = struct('plot_results', false, 'verbose', false, ...
        'max_iter', 50, 'tolerance', 1e-8, 'enforce_q_limits', false);
    pf = pfsolver.powerflow_newton_raphson(case_data, opts);
end
case_data = cases.case_kundur_two_area_classical();
M = case_data.machines;
if ~pf.converged
    error('kundur_ex126_sauer_pai_ssa:noConvergence', ...
        'Power-flow did not converge.');
end

% gamma factors (constant, machine pu)
R = M.reactances;
g_d1 = (R.Xdpp - R.Xl) / (R.Xdp - R.Xl);
g_q1 = (R.Xqpp - R.Xl) / (R.Xqp - R.Xl);
g_d2 = (1 - g_d1) / (R.Xdp - R.Xl);
g_q2 = (1 - g_q1) / (R.Xqp - R.Xl);
gamma = struct('d1',g_d1,'q1',g_q1,'d2',g_d2,'q2',g_q2);

[init, Ynet] = initialise_generators(pf, case_data, M, gamma);
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
% Remove the algebraic angle reference before forming the Schur complement.
% y(2) is the imaginary component of the slack-bus voltage; it is the same
% reference held fixed during the DAE Newton solve.
free_y = setdiff(1:size(Jyy,1), 2);
Ared_full = Jxx - Jxy(:,free_y) * (Jyy(free_y,free_y) \ Jyx(free_y,:));
% Drop the reference rotor angle (delta_1) to remove the mechanical angle
% reference from the state matrix.
keep = 2:size(Ared_full,1);
Ared = Ared_full(keep, keep);

lambda = eig(Ared);
[~, D] = eig(Ared);

result = struct();
result.Ared = Ared;
result.eigenvalues = lambda;
result.state_names = init.state_names(keep);
result.init = init;
result.mode_shapes = D;
result.frequency_Hz = abs(imag(lambda)) / (2*pi);
result.damping_ratio = -real(lambda) ./ (abs(lambda) + eps);
result.stable = all(real(lambda) < -1e-9);
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
function [init, Ynet] = initialise_generators(pf, case_data, M, gamma)
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

    % Transient EMFs from the steady-state differential equations and
    % stator equations (current out of machine):
    %   Vq = E'q - Ra Iq - X'd Id  =>  E'q = Vq + Ra Iq + X'd Id
    %   E'd = (Xq-X'q) Iq, with the delta above enforcing Vd consistency.
    Eqp = Vq + Ra_n*Iq + Xdp_n*Id;
    Edp = (Xq_n - Xqp_n)*Iq;
    % Subtransient flux linkages at steady state:
    %   psi''d = E'q - (X'd - Xl) Id
    %   psi''q = E'd + (X'q - Xl) Iq
    % With gamma interpolation this gives Eq'' = E'q - (X'd-X''d)Id
    % and Ed'' = E'd + (X'q-X''q)Iq, so the stator equations reduce to
    % the standard transient form at equilibrium.
    Psipd = Eqp - (Xdp_n - Xl_n)*Id;
    Psipq = Edp + (Xqp_n - Xl_n)*Iq;
    % Field voltage (constant)
    Eq = Eqp + (Xd_n - Xdp_n)*Id;   init.Efd(k) = Eq;
    init.Eqpi(k)=Eqp; init.Edpi(k)=Edp;
    init.Psipd(k)=Psipd; init.Psipq(k)=Psipq;

    x0((k-1)*6+1)=delta; x0((k-1)*6+2)=0;
    x0((k-1)*6+3)=Eqp; x0((k-1)*6+4)=Edp;
    x0((k-1)*6+5)=Psipd; x0((k-1)*6+6)=Psipq;

    init.state_names{(k-1)*6+1} = sprintf('\\delta_{%s}', M.units(k).gen_id);
    init.state_names{(k-1)*6+2} = sprintf('\\omega_{%s}', M.units(k).gen_id);
    init.state_names{(k-1)*6+3} = sprintf("E'_{q,%s}", M.units(k).gen_id);
    init.state_names{(k-1)*6+4} = sprintf("E'_{d,%s}", M.units(k).gen_id);
    init.state_names{(k-1)*6+5} = sprintf("\\psi''_{d,%s}", M.units(k).gen_id);
    init.state_names{(k-1)*6+6} = sprintf("\\psi''_{q,%s}", M.units(k).gen_id);
    init.H_sys(k) = M.units(k).H * (Sm/Sbase);
end
init.x0 = x0; init.ng = ng; init.w0 = w0;
init.zb_scale = zb_scale;

Ynet = build_network_admittance(pf, case_data, M);

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
function Ynet = build_network_admittance(pf, case_data, M)
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
    if Vmag>0 && (Pload~=0 || Qload~=0)
        Y(b,b) = Y(b,b) + (Pload-1i*Qload)/(Vmag^2);
    end
end
Ynet = Y;
end

% =========================================================================
function init = refine_initial_state(init, M, Ynet, base, gamma)
x = init.x0; y = init.y0;
zb_scale = init.zb_scale;
% Tm = Te at operating point
[Te0, Id0, Iq0, Vd0, Vq0] = te_at_op(x, y, init, M, Ynet, base, gamma, zb_scale);
init.Tm = Te0; init.Id=Id0; init.Iq=Iq0; init.Vd=Vd0; init.Vq=Vq0;

fixed_y = 2; free_y = setdiff(1:numel(y), fixed_y);
fixed_x = 1; free_x = setdiff(1:numel(x), fixed_x);
maxit = 200; tol = 1e-12;
for it = 1:maxit
    f = dae_f(x, y, init, M, Ynet, base, gamma);
    g = dae_g(x, y, init, M, Ynet, base, gamma, zb_scale);
    res = [f; g]; nr = norm(res);
    if nr < tol; break; end
    nx_free=numel(free_x); ny_free=numel(free_y); eps_p=1e-6;
    J = zeros(numel(f)+numel(g), nx_free+ny_free);
    for ii=1:nx_free
        i=free_x(ii); xp=x; xp(i)=xp(i)+eps_p; xm=x; xm(i)=xm(i)-eps_p;
        J(:,ii)=([dae_f(xp,y,init,M,Ynet,base,gamma);dae_g(xp,y,init,M,Ynet,base,gamma,zb_scale)] ...
               -[dae_f(xm,y,init,M,Ynet,base,gamma);dae_g(xm,y,init,M,Ynet,base,gamma,zb_scale)])/(2*eps_p);
    end
    for jj=1:ny_free
        j=free_y(jj); yp=y; yp(j)=yp(j)+eps_p; ym=y; ym(j)=ym(j)-eps_p;
        J(:,nx_free+jj)=([dae_f(x,yp,init,M,Ynet,base,gamma);dae_g(x,yp,init,M,Ynet,base,gamma,zb_scale)] ...
                 -[dae_f(x,ym,init,M,Ynet,base,gamma);dae_g(x,ym,init,M,Ynet,base,gamma,zb_scale)])/(2*eps_p);
    end
    step = J \ (-res);
    lambda = 0; res_new = inf;
    for tries = 1:10
        if lambda==0; st = step; else
            st = (J'*J + lambda*eye(size(J,2))) \ (J'*(-res));
        end
        x_new=x; x_new(free_x)=x_new(free_x)+st(1:nx_free);
        y_new=y; y_new(free_y)=y_new(free_y)+st(nx_free+1:end);
        rn = norm([dae_f(x_new,y_new,init,M,Ynet,base,gamma); ...
                   dae_g(x_new,y_new,init,M,Ynet,base,gamma,zb_scale)]);
        if rn < nr; x=x_new; y=y_new; res_new=rn; break; end
        if lambda==0; lambda=1e-6; else; lambda=lambda*10; end
    end
    if res_new >= nr; break; end
end
init.x0=x; init.y0=y; init.newton_iterations=it;
% Refresh constant operating inputs at the final equilibrium candidate.
[Te1, Id1, Iq1, Vd1, Vq1] = te_at_op(x, y, init, M, Ynet, base, gamma, zb_scale);
init.Tm = Te1; init.Id = Id1; init.Iq = Iq1; init.Vd = Vd1; init.Vq = Vq1;
R = M.reactances;
Sbase = base.S_base_MVA; Sm = M.base.S_MVA;
zb_scale_final = Sbase / Sm;
Xd_n = R.Xd * zb_scale_final;
Xdp_n = R.Xdp * zb_scale_final;
for kk = 1:init.ng
    Eqp_k = x((kk-1)*6+3);
    Psipd_k = x((kk-1)*6+5);
    gamma_d2_n = (1-gamma.d1) / (Xdp_n - R.Xl * zb_scale_final);
    Id_eff_k = gamma.d1*Id1(kk) + gamma_d2_n*(Eqp_k - Psipd_k);
    init.Efd(kk) = Eqp_k + (Xd_n - Xdp_n) * Id_eff_k;
end
f_final = dae_f(init.x0, init.y0, init, M, Ynet, base, gamma);
g_final = dae_g(init.x0, init.y0, init, M, Ynet, base, gamma, zb_scale);
init.newton_residual = norm([f_final; g_final]);
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
    Id_eff = gamma.d1*Id + gamma_d2_n*(Eqp - Psipd);
    Iq_eff = gamma.q1*Iq + gamma_q2_n*(Psipq - Edp);
    f((k-1)*6+3)=(init.Efd(k)-Eqp-(Xd_n-Xdp_n)*Id_eff)/TC.Tpd0;
    f((k-1)*6+4)=(-Edp+(Xq_n-Xqp_n)*Iq_eff)/TC.Tpq0;
    f((k-1)*6+5)=(Eqp-Psipd-(Xdp_n-Xl_n)*Id)/TC.Tppd0;
    f((k-1)*6+6)=(Edp-Psipq+(Xqp_n-Xl_n)*Iq)/TC.Tppq0;
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
