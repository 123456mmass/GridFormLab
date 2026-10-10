function probe_ne39_sssa_gauge_uncertainty()
%PROBE_NE39_SSSA_GAUGE_UNCERTAINTY  FD-scheme + step + participation bounds on
%   the gauge-quotiented NE39 spectrum. Establishes an ERROR BOUND for the
%   surviving near-axis pair instead of clipping it to zero, and compares
%   forward vs central differences on the SAME gauge quotient.
pf_init_paths();
s = cases.scenario_ne39_5sg_5ibr();
[devices,~] = stability.build_mixed_resource_devices( ...
    s.case_data, s.resources, s.scenario_opt);
eq = stability.mixed_equilibrium_solve(s.case_data, ...
    struct('devices',devices), struct('verbose',false));
dae = stability.composite_dae(s.case_data, devices, ...
    struct('full_kcl',true,'u_eq',eq.u_eq, ...
    'event_context',eq.equilibrium_context, ...
    'dynamic_state_indices',eq.dynamic_state_indices));
x0 = eq.x0; y0 = eq.y0; u = eq.u_eq; ec = eq.equilibrium_context;
nx = numel(x0); ny = numel(y0); Y = dae.Ynet;
active = eq.active_state_indices(:)';
m0 = build_model(s, eq, 3e-6);
Lq = m0.coordinate_quotient_left_map; Tq = m0.coordinate_quotient_right_map;
Tg = build_tangent(dae, y0, nx);      % full rotational tangent
Jfull = [m0.fx m0.fy; m0.gx m0.gy];

fprintf('--- step sweep: ||J*T|| and gauge-quotiented near-axis pair ---\n');
eps_list = [3e-5 1e-5 3e-6 1e-6 3e-7];
for e = eps_list
    m = build_model(s, eq, e);
    J = [m.fx m.fy; m.gx m.gy];
    jt = norm(J*Tg, inf);
    pr = pair_real(m.physical_eigenvalues);
    fprintf('eps=%.1e ||J*T||inf=%.3e  gauge_maxRe=%.6e  pair_Re=%.8e\n', ...
        e, jt, max(real(m.physical_eigenvalues)), pr);
end

% --- forward vs central differences on the SAME gauge quotient -------------
h = 3e-6;
[fxc, gxc] = dc_x(dae, x0, y0, u, ec, Y, nx, h);
[fy, gy] = dc_y(dae, x0, y0, u, ec, Y, ny, h);
Ac = fxc - fy*(gy\gxc);
Aq_c = Lq * Ac(active,active) * Tq;
epc = eig(Aq_c);
fprintf('--- forward vs central (h=%.1e) ---\n', h);
fprintf('forward gauge_maxRe=%.8e  pair_Re=%.8e\n', ...
    max(real(m0.physical_eigenvalues)), pair_real(m0.physical_eigenvalues));
fprintf('central gauge_maxRe=%.8e  pair_Re=%.8e  nPos=%d\n', ...
    max(real(epc)), pair_real(epc), sum(real(epc)>1e-6));

% --- participation of the surviving positive pair --------------------------
[V, D] = eig(m0.physical_A);
ev = diag(D); [~, ix] = min(abs(real(ev)) + (abs(imag(ev))<1));  % nearest-axis complex
if abs(imag(ev(ix))) > 1
    v = V(:, ix); w = abs(v); w = w/sum(w);
    [~, pk] = sort(w, 'descend');
    gi = m0.physical_state_global_indices;
    names = global_state_names(dae);
    fprintf('--- pair participation (top6) ---\n');
    for j = 1:min(6, numel(pk))
        fprintf('   %.4f  %s\n', w(pk(j)), names{gi(pk(j))});
    end
end
end

% --- helpers -------------------------------------------------------------
function m = build_model(s, eq, e)
m = stability.composite_sssa_model(eq.devices, eq.x0, eq.y0, s.case_data, ...
    struct('full_kcl',true,'u_eq',eq.u_eq,'event_context',eq.equilibrium_context, ...
    'active_state_indices',eq.active_state_indices,'fd_eps',e, ...
    'reference_device_index',eq.reference.device_index));
end

function T = build_tangent(dae, y0, nx)
Tx = zeros(nx,1);
cands = {'delta','gfl_delta_PLL','delta_PLL','gfm_delta_VSG','gfm_delta_PLL','delta_VSG'};
for dk = 1:numel(dae.devices)
    nm = cellstr(string(dae.devices(dk).state_names)); pos = [];
    for c = cands, p = find(strcmpi(nm,c{1}),1); if ~isempty(p), pos = p; break; end; end
    if ~isempty(pos), Tx(dae.device_offsets(dk)+pos) = 1; end
end
ny = numel(y0); Ty = zeros(ny,1);
for b = 1:ny/2, re = y0(2*b-1); im = y0(2*b); Ty(2*b-1) = -im; Ty(2*b) = re; end
T = [Tx; Ty];
end

function [fx, gx] = dc_x(dae, x0, y0, u, ec, Y, nx, h)
fx = zeros(nx,nx); gx = zeros(numel(y0),nx);
for j = 1:nx
    xp = x0; xp(j) = xp(j)+h; xm = x0; xm(j) = xm(j)-h;
    fx(:,j) = (dae.dae_f(0,xp,y0,u,ec) - dae.dae_f(0,xm,y0,u,ec))/(2*h);
    gx(:,j) = (dae.dae_g(0,xp,y0,Y,u,ec) - dae.dae_g(0,xm,y0,Y,u,ec))/(2*h);
end
end

function [fy, gy] = dc_y(dae, x0, y0, u, ec, Y, ny, h)
fy = zeros(numel(x0),ny); gy = zeros(ny,ny);
for j = 1:ny
    yp = y0; yp(j) = yp(j)+h; ym = y0; ym(j) = ym(j)-h;
    fy(:,j) = (dae.dae_f(0,x0,yp,u,ec) - dae.dae_f(0,x0,ym,u,ec))/(2*h);
    gy(:,j) = (dae.dae_g(0,x0,yp,Y,u,ec) - dae.dae_g(0,x0,ym,Y,u,ec))/(2*h);
end
end

function r = pair_real(ev)
c = ev(abs(imag(ev)) > 1);
if isempty(c), r = NaN; return; end
[~, ix] = min(abs(real(c))); r = real(c(ix));
end

function names = global_state_names(dae)
names = {};
for k = 1:numel(dae.devices)
    for j = 1:dae.devices(k).nx
        names{end+1} = sprintf('%s:%s', dae.devices(k).device_id, dae.devices(k).state_names{j}); %#ok<AGROW>
    end
end
end
