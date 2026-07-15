function out = verify_sg_tm_slack_contract()
%VERIFY_SG_TM_SLACK_CONTRACT  Diagnostic all-KCL SG-reference equilibrium.
%   Validation-only probe (off the production path). It tests the square
%   formulation
%       z = [x_active; y_except_ImVref; Tm_reference]
%       R = [f_active; g_all]
%   for the SG_ON + four-GFL IEEE14 configuration. The angle gauge removes
%   Im(Vref) as a coordinate; no physical KCL row is removed.
%
%   The SG production device currently captures Tm and has nu=0. This probe
%   wraps only its swing RHS so that u_dev(1)=Tm while retaining the exact
%   production current, stator, flux, and reconstruction closures.

root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(root);
pf_init_paths();

c = cases.case_ieee14_1sg_4ibr_auto_vsg();
modes = struct('device_id',{'IBR2','IBR3','IBR6','IBR8'}, ...
    'mode',{'gfl','gfl','gfl','gfl'});
dispatch = struct('IBR2',40.0,'IBR3',0.0,'IBR6',0.0,'IBR8',0.0);
devices = ibr.build_ieee14_sg_ibr_devices(c,modes,dispatch);

% Use the current SG-reference equilibrium only as an initial point. Its
% residual/KCL metrics are reported as seed diagnostics; the independent
% formulation below still rebuilds and solves its own 57x57 residual.
legacy = stability.mixed_equilibrium_solve(c,struct('devices',devices), ...
    struct('verbose',false));
if ~legacy.converged
    error('verify_sg_tm_slack_contract:legacyInit', ...
        'Legacy SG_ON equilibrium did not provide an initial point: %s', ...
        legacy.failure_reason);
end

sg_index = find(strcmp({devices.device_type},'sg_emf6_composite'),1);
if isempty(sg_index)
    error('verify_sg_tm_slack_contract:noSG','No SG composite device found.');
end
sg = devices(sg_index);
ec = struct('hybrid_state',stability.ts_hybrid_state_init(devices));
sg_xr = device_range(devices,sg_index,'nx');
if sg.nu == 0
    % Historical ABI: faithfully expose only the captured Tm in this probe.
    sg_out = sg.reconstruct(0,legacy.x0(sg_xr),legacy.y0,[],ec);
    Tm0 = sg_out.Tm;
    scale = c.mpc.baseMVA / c.machines.base.S_MVA;
    H_system = c.machines.units.H / scale;
    base_f = sg.f;
    devices(sg_index).nu = 1;
    devices(sg_index).u0 = Tm0;
    devices(sg_index).input_names = {'Tm_reference_pu'};
    devices(sg_index).f = @(t,x,y,u,event_context) ...
        sg_rhs_with_tm(base_f,t,x,y,u,event_context,Tm0,H_system);
    abi = 'diagnostic wrapper over historical nu=0 SG';
elseif sg.nu == 2 && isequal(string(sg.input_names(:)),["Tm";"Efd"])
    % Candidate production ABI under concurrent review: vary Tm only and hold
    % Efd exactly at its PF-derived input. This isolates the requested claim.
    Tm0 = sg.u0(1);
    abi = 'native u=[Tm;Efd], Efd held fixed';
else
    error('verify_sg_tm_slack_contract:unsupportedSGABI', ...
        'Expected SG nu=0 or nu=2 [Tm;Efd], got nu=%d.',sg.nu);
end

dae = stability.composite_dae(c,devices,struct('load_model','cz_p_cz_q'));
active = legacy.active_state_indices(:);
nx_active = numel(active);
gauge_var = 2*sg.bus_position;
y_free = setdiff((1:numel(legacy.y0)).',gauge_var,'stable');
x_anchor = dae.x0(:);
y_anchor = dae.y0(:);
y_anchor(gauge_var) = 0;
u_anchor = dae.u0(:);
sg_ur = device_range(devices,sg_index,'nu');
sg_tm_index = sg_ur(1);

z0 = [x_anchor(active); y_anchor(y_free); Tm0];
residual_fn = @(z) all_kcl_residual(z,dae,x_anchor,y_anchor,u_anchor, ...
    active,y_free,sg_tm_index,ec);
fd_eps = 3e-6;
jacobian_fn = @(z) central_fd(residual_fn,z,fd_eps);
[z,niter,converged,residual_norm,rcond_val,J] = ...
    stability.composite_newton(z0,residual_fn,jacobian_fn,1e-8,300,false);

[x,y,u] = unpack(z,x_anchor,y_anchor,u_anchor,active,y_free,sg_tm_index);
f = dae.dae_f(0,x,y,u,ec);
g = dae.dae_g(0,x,y,dae.Ynet,u,ec);
Tm = u(sg_tm_index);
sg_u = u(sg_ur);
Pe = devices(sg_index).electrical_power(0,x(sg_xr),y,sg_u,ec);
Vsg = complex(y(2*sg.bus_position-1),y(2*sg.bus_position));
Isg = devices(sg_index).current_injection(0,x(sg_xr),y,sg_u,ec);
Ssg = Vsg*conj(Isg);

out = struct();
out.converged = converged;
out.iterations = niter;
out.residual_norm = residual_norm;
out.physical_kcl_norm = norm(g,inf);
out.active_f_norm = norm(f(active),inf);
out.rcond = rcond_val;
out.jacobian_size = size(J);
out.n_unknown = numel(z);
out.n_residual = numel(residual_fn(z));
out.Tm_initial_pu = Tm0;
out.Tm_solved_pu = Tm;
out.Tm_solved_MW = Tm*c.mpc.baseMVA;
out.Pe_airgap_pu = Pe;
out.swing_balance_error = abs(Tm-Pe);
out.Efd_held_pu = NaN;
if numel(sg_u) >= 2, out.Efd_held_pu = sg_u(2); end
out.Vref_magnitude_pu = abs(Vsg);
out.SG_terminal_P_pu = real(Ssg);
out.SG_terminal_Q_pu = imag(Ssg);
out.gauge_variable = gauge_var;
out.gauge_value = y(gauge_var);
out.seed_residual = legacy.residual_norm;
out.seed_physical_kcl_norm = legacy.physical_kcl_norm;
out.sg_abi = abi;

fprintf('SG Tm-slack all-KCL probe\n');
fprintf('  converged=%d iterations=%d residual=%.12g KCL=%.12g active-f=%.12g\n', ...
    converged,niter,residual_norm,out.physical_kcl_norm,out.active_f_norm);
fprintf('  rcond=%.12g J=%dx%d square=%d gauge Im(V%d)=%.12g\n', ...
    rcond_val,size(J,1),size(J,2),out.n_unknown==out.n_residual, ...
    sg.bus_id,out.gauge_value);
fprintf('  Tm: initial=%.12g pu solved=%.12g pu (%.9f MW) Pe=%.12g pu error=%.3g\n', ...
    Tm0,Tm,out.Tm_solved_MW,Pe,out.swing_balance_error);
fprintf('  held Efd=%.12g pu |Vref|=%.12g pu SG terminal S=%.12g%+.12gj pu\n', ...
    out.Efd_held_pu,out.Vref_magnitude_pu,real(Ssg),imag(Ssg));
fprintf('  seed equilibrium: residual=%.12g physical KCL norm=%.12g\n', ...
    legacy.residual_norm,legacy.physical_kcl_norm);
fprintf('  SG ABI: %s\n',abi);
end

function dx = sg_rhs_with_tm(base_f,t,x,y,u,event_context,Tm0,H_system)
if ~isnumeric(u) || numel(u) ~= 1 || ~isfinite(u(1))
    error('verify_sg_tm_slack_contract:badTm','Tm input must be one finite scalar.');
end
dx = base_f(t,x,y,zeros(0,1),event_context);
% Exact correction to 2H*domega/dt = Tm - Te - D*omega.
dx(2) = dx(2) + (u(1)-Tm0)/(2*H_system);
end

function r = all_kcl_residual(z,dae,x_anchor,y_anchor,u_anchor,active,y_free,sg_tm_index,ec)
[x,y,u] = unpack(z,x_anchor,y_anchor,u_anchor,active,y_free,sg_tm_index);
f = dae.dae_f(0,x,y,u,ec);
g = dae.dae_g(0,x,y,dae.Ynet,u,ec);
r = [f(active); g];
end

function [x,y,u] = unpack(z,x_anchor,y_anchor,u_anchor,active,y_free,sg_tm_index)
na = numel(active);
nyf = numel(y_free);
x = x_anchor;
x(active) = z(1:na);
y = y_anchor;
y(y_free) = z(na+(1:nyf));
u = u_anchor;
u(sg_tm_index) = z(end);
end

function J = central_fd(fun,z,h)
r0 = fun(z);
J = zeros(numel(r0),numel(z));
for k = 1:numel(z)
    hk = h*max(1,abs(z(k)));
    zp = z; zm = z;
    zp(k) = zp(k)+hk;
    zm(k) = zm(k)-hk;
    J(:,k) = (fun(zp)-fun(zm))/(2*hk);
end
end

function range = device_range(devices,index,kind)
counts = arrayfun(@(d) d.(kind),devices);
first = sum(counts(1:index-1))+1;
range = first:(first+counts(index)-1);
end
