function tests = test_ieee14_sg_off_gfm_sssa_contract()
%TEST_IEEE14_SG_OFF_GFM_SSSA_CONTRACT  Full-KCL SSSA equation-sharing gates.
%   Uses the production SG_OFF + index-selected GFM equilibrium, then checks
%   that composite_sssa_model differentiates the same pure-KCL composite f/g
%   closures at the exact solved u/context and projects before eig.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();

c = cases.case_ieee14_1sg_4ibr_auto_vsg();
modes = struct('device_id',{'IBR2','IBR3','IBR6','IBR8'}, ...
    'mode',{'GFM','gfl','gfl','gfl'});
dispatch = struct('IBR2',109.7,'IBR3',49.8,'IBR6',49.8,'IBR8',49.8);
devices = ibr.build_ieee14_sg_ibr_devices(c,modes,dispatch);
devices(1).initial_online = false;
devices(1).mode = 'breaker_open';
cfg = struct('devices',devices,'selected_gfm_indices',2, ...
    'n_gfm_required',1,'reference_resource_index',2);
eq = stability.mixed_equilibrium_solve(c,cfg,struct('verbose',false));
testCase.assertTrue(eq.converged,eq.failure_reason);
testCase.assertLessThan(eq.physical_kcl_norm,1e-6);

% Deliberately pass the pre-solve device array. Its scheduled reference P in
% dae.u0 differs from the solved balancing P; opt.u_eq must therefore be used.
opt = struct('full_kcl',true,'u_eq',eq.u_eq, ...
    'event_context',eq.equilibrium_context, ...
    'active_state_indices',eq.active_state_indices);
sssa = stability.composite_sssa_model(devices,eq.x0,eq.y0,c,opt);
dae = stability.composite_dae(c,devices,struct('load_model','cz_p_cz_q'));

testCase.TestData.case_data = c;
testCase.TestData.devices = devices;
testCase.TestData.eq = eq;
testCase.TestData.sssa = sssa;
testCase.TestData.dae = dae;
end

% =========================================================================
function test_full_kcl_dimensions_conditioning_and_spectrum(testCase)
eq = testCase.TestData.eq;
s = testCase.TestData.sssa;

testCase.verifyTrue(s.full_kcl);
testCase.verifyEmpty(s.kcl_rows_replaced, ...
    'Pure-KCL SSSA must not replace a physical KCL row with a vcon.');
testCase.verifyEqual(s.nx_total,66,'AbsTol',0);
testCase.verifyEqual(s.nx_active,29,'AbsTol',0);
testCase.verifyEqual(size(s.fx),[66 66],'AbsTol',0);
testCase.verifyEqual(size(s.fy),[66 28],'AbsTol',0);
testCase.verifyEqual(size(s.gx),[28 66],'AbsTol',0);
testCase.verifyEqual(size(s.gy),[28 28],'AbsTol',0);
testCase.verifyEqual(size(s.A_full),[66 66],'AbsTol',0);
testCase.verifyEqual(size(s.A),[29 29],'AbsTol',0);
testCase.verifyEqual(numel(s.eigenvalues),29,'AbsTol',0);
testCase.verifyGreaterThan(s.gy_rcond,1e-10);
testCase.verifyGreaterThan(s.gy_rcond,s.gy_rcond_min);
testCase.verifyTrue(all(isfinite(s.A_full(:))));
testCase.verifyTrue(all(isfinite(s.A(:))));
testCase.verifyTrue(all(isfinite(s.eigenvalues(:))));
testCase.verifyLessThan(s.active_f_residual_norm,1e-8);
testCase.verifyLessThan(s.physical_kcl_residual_norm,1e-6);
testCase.verifyEqual(s.active_state_indices,eq.active_state_indices,'AbsTol',0);
testCase.verifyTrue(s.no_eig_delete);
testCase.verifyEqual(s.reduction_method, ...
    'full_kcl_schur_active_state_galerkin_before_eig');
end

% =========================================================================
function test_exact_u_and_event_context_propagation(testCase)
eq = testCase.TestData.eq;
s = testCase.TestData.sssa;
dae = testCase.TestData.dae;

testCase.verifyEqual(s.u_eq,eq.u_eq,'AbsTol',0);
testCase.verifyEqual(s.event_context,eq.equilibrium_context);
testCase.verifyGreaterThan(norm(eq.u_eq-dae.u0,inf),1e-3, ...
    'Solved reference-GFM P must differ from the pre-solve scheduled input.');

f_exact = dae.dae_f(0,eq.x0,eq.y0,eq.u_eq,eq.equilibrium_context);
g_exact = dae.dae_g(0,eq.x0,eq.y0,dae.Ynet,eq.u_eq,eq.equilibrium_context);
testCase.verifyEqual(s.f0,f_exact,'AbsTol',0, ...
    'SSSA f0 uses the exact solved u and immutable equilibrium context.');
testCase.verifyEqual(s.g0,g_exact,'AbsTol',0, ...
    'SSSA g0 uses the exact solved u/context and every physical KCL row.');

% Empty context would silently put SG1 back online; prove context propagation
% is physically material rather than output metadata only.
f_stale = dae.dae_f(0,eq.x0,eq.y0,eq.u_eq,struct());
g_stale = dae.dae_g(0,eq.x0,eq.y0,dae.Ynet,eq.u_eq,struct());
testCase.verifyGreaterThan(max(norm(f_stale-s.f0,inf), ...
    norm(g_stale-s.g0,inf)),1e-3);
end

% =========================================================================
function test_fd_equation_sharing_and_schur_projection(testCase)
eq = testCase.TestData.eq;
s = testCase.TestData.sssa;
dae = testCase.TestData.dae;
h = s.fd_eps;

% One active state column: independently differentiate both exact closures.
jx = eq.active_state_indices(1);
xp = eq.x0;
xp(jx) = xp(jx) + h;
fx_col = (dae.dae_f(0,xp,eq.y0,eq.u_eq,eq.equilibrium_context)-s.f0)/h;
gx_col = (dae.dae_g(0,xp,eq.y0,dae.Ynet,eq.u_eq, ...
    eq.equilibrium_context)-s.g0)/h;
testCase.verifyEqual(s.fx(:,jx),fx_col,'AbsTol',1e-12);
testCase.verifyEqual(s.gx(:,jx),gx_col,'AbsTol',1e-12);

% One algebraic voltage column at the selected GFM bus.
jy = 2*eq.reference.bus_position-1;
yp = eq.y0;
yp(jy) = yp(jy) + h;
fy_col = (dae.dae_f(0,eq.x0,yp,eq.u_eq,eq.equilibrium_context)-s.f0)/h;
gy_col = (dae.dae_g(0,eq.x0,yp,dae.Ynet,eq.u_eq, ...
    eq.equilibrium_context)-s.g0)/h;
testCase.verifyEqual(s.fy(:,jy),fy_col,'AbsTol',1e-12);
testCase.verifyEqual(s.gy(:,jy),gy_col,'AbsTol',1e-12);

% In-house Schur equation and projection are independently reconstructed.
A_oracle = s.fx-s.fy*(s.gy\s.gx);
testCase.verifyEqual(s.A_full,A_oracle,'AbsTol',1e-11);
testCase.verifyEqual(s.A,A_oracle(eq.active_state_indices, ...
    eq.active_state_indices),'AbsTol',1e-11);
end

% =========================================================================
function test_full_kcl_fail_closed_and_source_guards(testCase)
c = testCase.TestData.case_data;
d = testCase.TestData.devices;
eq = testCase.TestData.eq;
testCase.verifyError(@() stability.composite_sssa_model( ...
    d,eq.x0,eq.y0,c,struct('full_kcl',true)), ...
    'composite_sssa_model:missingFullKclOption');
bad = struct('full_kcl',true,'u_eq',eq.u_eq, ...
    'event_context',eq.equilibrium_context, ...
    'active_state_indices',eq.active_state_indices(2:end));
testCase.verifyError(@() stability.composite_sssa_model( ...
    d,eq.x0,eq.y0,c,bad), ...
    'composite_sssa_model:activeStateMismatch');

src = fileread(fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
    '+stability','composite_sssa_model.m'));
for fn = {'fsolve','optimoptions','fmincon','fminsearch','lsqnonlin','pinv'}
    testCase.verifyFalse(contains(src,fn{1}),['No ' fn{1} ' in SSSA path.']);
end
testCase.verifyTrue(contains(src,'gy\gx'));
testCase.verifyTrue(contains(src,'eig(A)'));
end
