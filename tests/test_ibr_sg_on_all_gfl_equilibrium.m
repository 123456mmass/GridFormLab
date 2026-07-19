function tests = test_ibr_sg_on_all_gfl_equilibrium()
%TEST_IBR_SG_ON_ALL_GFL_EQUILIBRIUM  SG1 + four GFL-RMS10 normal operation.
%   The independent network oracle uses the composite DAE's frozen
%   constant-admittance load contract. The SG oracle directly evaluates the
%   stationary EMF6 equations used by synchronous_emf6_ssa for the identical
%   terminal voltage and P+jQ; neither oracle consumes a solved DAE state.
tests = functiontests(localfunctions);
end

function setupOnce(tc)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();

opt = all_gfl_options();
base = cases.scenario_ieee14_1sg_4ibr(struct( ...
    'ibr_profile',opt.ibr_profile));
[scenario,selection] = stability.ibr_configure_scenario(base,opt);
[devices,~] = stability.build_mixed_resource_devices( ...
    scenario.case_data,scenario.resources,scenario.scenario_opt);
dae = stability.composite_dae(scenario.case_data,devices, ...
    struct('load_model','cz_p_cz_q'));
event_context = struct('hybrid_state', ...
    stability.ts_hybrid_state_init(devices));
init = stability.mixed_ibr_sg_on_gfl_initialize( ...
    scenario.case_data,dae,event_context,struct());
eq = stability.mixed_equilibrium_solve(scenario.case_data, ...
    struct('devices',devices),struct('verbose',false));

tc.TestData.opt = opt;
tc.TestData.scenario = scenario;
tc.TestData.selection = selection;
tc.TestData.devices = devices;
tc.TestData.dae = dae;
tc.TestData.event_context = event_context;
tc.TestData.init = init;
tc.TestData.eq = eq;
end

function test_mode_aware_seed_has_machine_zero_residual_blocks(tc)
dae = tc.TestData.dae;
init = tc.TestData.init;
ec = tc.TestData.event_context;
tc.verifyTrue(init.applicable);
tc.verifyTrue(init.converged,init.failure_reason);

f = dae.dae_f(0,init.x0,init.y0,init.u0,ec);
g = dae.dae_g(0,init.x0,init.y0,dae.Ynet,init.u0,ec);
for k = 1:numel(dae.devices)
    xr = dae.device_offsets(k)+(1:dae.devices(k).nx);
    tc.verifyLessThan(norm(f(xr),inf),1e-8,dae.devices(k).device_id);
end
% Every real and imaginary physical KCL row is retained.
tc.verifyLessThan(max(abs(g)),1e-8);
end

function test_sg_stationary_initializer_matches_emf6_oracle(tc)
s = tc.TestData.scenario;
dae = tc.TestData.dae;
init = tc.TestData.init;
ec = tc.TestData.event_context;
sg = dae.devices(1);
V = complex(init.y0(1:2:end),init.y0(2:2:end));
row = find(init.pf.external_bus_ids==sg.bus_id,1);
P = init.pf.P_generation(row);
Q = init.pf.Q_generation(row);

emf = stability.synchronous_emf6_ssa(s.case_data, ...
    struct('load_model','cz_p_cz_q'));
[x_oracle,u_oracle,I_oracle] = emf_stationary_oracle( ...
    V(sg.bus_position),P,Q,emf.machine);
x_actual = sg.equilibrium_initialize(V(sg.bus_position),P,Q,ec);
tc.verifyEqual(x_actual,x_oracle,'AbsTol',1e-12);
tc.verifyEqual(init.u0(1:2),u_oracle,'AbsTol',1e-12);

I_actual = sg.current_injection(0,x_actual,init.y0,init.u0(1:2),ec);
tc.verifyEqual(I_actual,I_oracle,'AbsTol',1e-12);
end

function test_all_gfl_equilibrium_and_sssa_publish_complete_state_set(tc)
eq = tc.TestData.eq;
s = tc.TestData.scenario;
tc.verifyTrue(eq.converged,eq.failure_reason);
tc.verifyLessThan(eq.residual_norm,1e-8);
tc.verifyLessThan(eq.physical_kcl_norm,1e-8);
tc.verifyEqual(numel(eq.active_state_indices),45);

sssa = stability.composite_sssa_model(eq.devices,eq.x0,eq.y0, ...
    s.case_data,struct('full_kcl',true,'u_eq',eq.u_eq, ...
    'event_context',eq.equilibrium_context, ...
    'active_state_indices',eq.active_state_indices,'fd_eps',3e-6));
tc.verifyEqual(size(sssa.A),[45 45]);
tc.verifyEqual(numel(sssa.eigenvalues),45);
tc.verifyTrue(all(isfinite(sssa.eigenvalues)));
tc.verifyLessThan(sssa.active_f_residual_norm,1e-8);
tc.verifyLessThan(sssa.physical_kcl_residual_norm,1e-8);
end

function test_all_gfl_launcher_sssa_no_longer_fails_closed(tc)
opt = tc.TestData.opt;
opt.ibr_analysis = 'sssa';
r = solve_case('analysis','ibr','case','ieee14_1sg_4ibr','options',opt);
tc.verifyTrue(r.converged);
tc.verifyTrue(r.equilibrium.converged);
tc.verifyTrue(r.sssa.execution_converged);
tc.verifyEqual(size(r.sssa.A),[45 45]);
tc.verifyEqual(numel(r.sssa.eigenvalues),45);
end

function test_all_gfl_event_free_ts_starts_from_same_equilibrium(tc)
eq = tc.TestData.eq;
s = tc.TestData.scenario;
opt = struct('t_end',0.02,'dt',0.01,'verbose',false, ...
    'u_eq',eq.u_eq,'event_context',eq.equilibrium_context, ...
    'dynamic_state_indices',eq.dynamic_state_indices,'full_kcl',true);
[ts,meta] = stability.ts_simulate_composite( ...
    s.case_data,eq.devices,eq.x0,eq.y0,opt);
tc.verifyTrue(ts.converged);
tc.verifyTrue(meta.full_kcl);
tc.verifyEqual(ts.accepted_steps,2);
tc.verifyTrue(all(isfinite(ts.x_traj(:))));
tc.verifyTrue(all(isfinite(ts.y_traj(:))));
end

function test_pf_reporting_uses_committed_all_gfl_map(tc)
opt = all_gfl_options();
opt.ibr_analysis = 'pf';
text = evalc("r = solve_case('analysis','ibr','case','ieee14_1sg_4ibr','options',opt);");
tc.verifyTrue(r.converged);
tc.verifySubstring(text, ...
    'Profile : RMS10 configurable mix | SG=1, GFL-RMS10=4');
tc.verifySubstring(text,'IBR2    2      GFL-RMS10');
tc.verifyFalse(contains(text,'GFM-13'));
tc.verifyFalse(contains(text,'0xGFM'));
end

function opt = all_gfl_options()
opt = wizard.defaults_for_method('ibr','ieee14_1sg_4ibr');
opt.initial_gfm_count = 0;
opt.initial_gfl_count = 4;
opt.initial_gfm_indices = [];
opt.initial_reference_resource_index = [];
opt.ibr_events = struct('enabled',false);
opt.plot_results = false;
opt.plot_visible = false;
opt.verbose = false;
end

function [x,u,I] = emf_stationary_oracle(V,P,Q,m)
I = conj((P+1i*Q)/V);
delta = angle(V+(m.Ra(1)+1i*m.Xq(1))*I);
for k = 1:30
    r = angle_residual(delta,V,I,m);
    if abs(r)<=1e-12, break; end
    h = 1e-6;
    dr = (angle_residual(delta+h,V,I,m)- ...
        angle_residual(delta-h,V,I,m))/(2*h);
    delta = delta-r/dr;
end
assert(abs(angle_residual(delta,V,I,m))<=1e-9);
[Id,Iq] = stability.kundur_book_dq(I,delta);
[Vd,Vq] = stability.kundur_book_dq(V,delta);
Eqpp = Vq+m.Ra(1)*Iq+m.Xdpp(1)*Id;
Edpp = Vd+m.Ra(1)*Id-m.Xqpp(1)*Iq;
Eqp = Eqpp+(m.Xdp(1)-m.Xdpp(1))*Id;
Edp = Edpp-(m.Xqp(1)-m.Xqpp(1))*Iq;
if m.Tpq0(1)==0, Edp=0; end
Efd = m.d_d(1)*Eqp-m.c_d(1)*Eqpp;
Te = Vd*Id+Vq*Iq+m.Ra(1)*(Id^2+Iq^2);
x = [delta;0;Eqp;Edp;Eqpp;Edpp];
u = [Te;Efd];
end

function r = angle_residual(delta,V,I,m)
[Id,Iq] = stability.kundur_book_dq(I,delta);
[Vd,~] = stability.kundur_book_dq(V,delta);
r = Vd+m.Ra(1)*Id-m.Xq(1)*Iq;
end
