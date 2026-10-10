function tests = test_ne39_sssa_mode_validation()
%TEST_NE39_SSSA_MODE_VALIDATION  Characterise the NE39 SSSA positive-real mode.
%   The full-active NE39 SSSA exposes a small positive REAL eigenvalue (about
%   +1.1e-2 at the default fd_eps=3e-6). This file establishes what it IS,
%   using the FULL rotational-symmetry tangent -- every SG rotor angle AND every
%   IBR PLL/VSG angle, plus the algebraic bus-voltage rotation -- and the
%   engine's gauge quotient, which removes ONLY the common-rotation coordinate
%   and keeps every relative angle:
%     - J*T ~= 0 (gauge invariance), with the residual scaling as the FD step
%       O(eps), i.e. the residual is the finite-difference truncation only;
%     - the positive real mode is REMOVED by the gauge quotient (one near-zero
%       coordinate), so it is the common-angle gauge direction, not physics;
%     - the surviving positive pair is reported with its step/central-difference
%       convergence (about +2.3006e-5), NOT clipped to zero and NOT called
%       stable.
%   These tests are EVIDENCE about the spectrum; they are not a stability
%   certificate.
tests = functiontests(localfunctions);
end

function setupOnce(tc)
addpath(fileparts(fileparts(mfilename('fullpath'))));
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
tc.TestData.s = s; tc.TestData.eq = eq; tc.TestData.dae = dae;
end

function test_rotational_tangent_is_gauge_invariant(tc)
% J*T must vanish; its residual is FD truncation, so it shrinks ~linearly with
% the step. That is the gauge invariance the quotient relies on.
s = tc.TestData.s; eq = tc.TestData.eq; dae = tc.TestData.dae;
T = full_tangent(dae, eq.y0, numel(eq.x0));
m1 = build(s, eq, 1e-5);
m2 = build(s, eq, 3e-6);
j1 = norm([m1.fx m1.fy; m1.gx m1.gy]*T, inf);
j2 = norm([m2.fx m2.fy; m2.gx m2.gy]*T, inf);
tc.verifyLessThan(j2, 1e-3, 'J*T must be ~0 at the default step');
tc.verifyLessThan(j2, j1, 'J*T residual must shrink with the FD step');
end

function test_gauge_quotient_removes_the_positive_real_mode(tc)
% The full spectrum's +1.1e-2 real mode is the gauge coordinate: after the
% engine's relative-angle quotient the max real part collapses to ~1e-5.
s = tc.TestData.s; eq = tc.TestData.eq;
m = build(s, eq, 3e-6);
tc.verifyGreaterThan(max(real(m.eigenvalues)), 1e-3);
tc.verifyLessThan(max(real(m.physical_eigenvalues)), 1e-4);
tc.verifyLessThan(numel(m.physical_eigenvalues), numel(m.eigenvalues));
tc.verifyEqual(m.physical_reduction_method, ...
    'common_sg_ibr_network_angle_quotient');
end

function test_surviving_pair_is_weakly_positive_not_clipped(tc)
% After gauge, the maximum real part is a genuinely-but-weakly positive pair.
% Report it; do not clip it to zero, do not call it stable.
s = tc.TestData.s; eq = tc.TestData.eq;
m = build(s, eq, 3e-6);
rp = max(real(m.physical_eigenvalues));
tc.verifyGreaterThan(rp, 0, 'the surviving mode is positive (not clipped)');
tc.verifyLessThan(rp, 1e-4, 'but it is a weak (marginal) mode');
% Forward-vs-central agreement bounds it: central (O(eps^2)) at h=3e-6 must be
% within a tight band of the forward value, so the sign is not an FD artifact.
mc = central_gauged(s, eq, tc.TestData.dae, 3e-6);
tc.verifyEqual(max(real(mc)), rp, 'AbsTol', 1e-6);
end

function test_surviving_pair_participation_is_rotor_and_pll(tc)
% The surviving pair is an electromechanical/controller mode (SG rotor angles
% + IBR PLL angles), not a DC-only mode.
s = tc.TestData.s; eq = tc.TestData.eq;
m = build(s, eq, 3e-6);
[V, D] = eig(m.physical_A); ev = diag(D);
c = find(abs(imag(ev)) > 1);
tc.verifyNotEmpty(c);
[~, k] = min(abs(real(ev(c)))); v = V(:, c(k));
w = abs(v); w = w/sum(w);
names = {};
for i = 1:numel(m.physical_state_global_indices)
    gi = m.physical_state_global_indices(i);
    names{i} = local_name(tc.TestData.dae, gi);
end
[~, pk] = sort(w, 'descend');
top = names(pk(1:min(4,numel(pk))));
tc.verifyTrue(any(contains(top,'delta', 'IgnoreCase', true)), ...
    'rotor/PLL angle must dominate the surviving pair');
end

% --- helpers -------------------------------------------------------------
function m = build(s, eq, e)
m = stability.composite_sssa_model(eq.devices, eq.x0, eq.y0, s.case_data, ...
    struct('full_kcl',true,'u_eq',eq.u_eq, ...
    'event_context',eq.equilibrium_context, ...
    'active_state_indices',eq.active_state_indices,'fd_eps',e, ...
    'reference_device_index',eq.reference.device_index));
end

function T = full_tangent(dae, y0, nx)
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

function rp = central_gauged(s, eq, dae, h)
% Rebuild the Jacobian by CENTRAL differences and apply the SAME gauge quotient.
x0 = eq.x0; y0 = eq.y0; u = eq.u_eq; ec = eq.equilibrium_context; Y = dae.Ynet;
nx = numel(x0); ny = numel(y0);
m = build(s, eq, h);
Lq = m.coordinate_quotient_left_map; Tq = m.coordinate_quotient_right_map;
fx = zeros(nx,nx); gx = zeros(ny,nx);
for j = 1:nx
    xp = x0; xp(j) = xp(j)+h; xm = x0; xm(j) = xm(j)-h;
    fx(:,j) = (dae.dae_f(0,xp,y0,u,ec) - dae.dae_f(0,xm,y0,u,ec))/(2*h);
    gx(:,j) = (dae.dae_g(0,xp,y0,Y,u,ec) - dae.dae_g(0,xm,y0,Y,u,ec))/(2*h);
end
fy = zeros(nx,ny); gy = zeros(ny,ny);
for j = 1:ny
    yp = y0; yp(j) = yp(j)+h; ym = y0; ym(j) = ym(j)-h;
    fy(:,j) = (dae.dae_f(0,x0,yp,u,ec) - dae.dae_f(0,x0,ym,u,ec))/(2*h);
    gy(:,j) = (dae.dae_g(0,x0,yp,Y,u,ec) - dae.dae_g(0,x0,ym,Y,u,ec))/(2*h);
end
Ac = fx - fy*(gy\gx);
active = eq.active_state_indices(:)';
Aq = Lq * Ac(active,active) * Tq;
rp = max(real(eig(Aq)));
end

function name = local_name(dae, gi)
name = sprintf('global%d', gi);
for k = 1:numel(dae.devices)
    off = dae.device_offsets(k);
    if gi > off && gi <= off + dae.devices(k).nx
        name = sprintf('%s:%s', dae.devices(k).device_id, ...
            dae.devices(k).state_names{gi-off});
        return;
    end
end
end
