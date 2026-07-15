function tests = test_ieee14_sg_reference_equilibrium
%TEST_IEEE14_SG_REFERENCE_EQUILIBRIUM  Physical SG REF/all-KCL contract.
%   The REF bus fixes |V| and angle. Tm/Efd are equilibrium-solved control
%   outputs, then held constant by TS/SSSA. No physical KCL row is removed.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
modes = struct('device_id',{'IBR2','IBR3','IBR6','IBR8'}, ...
    'mode',{'gfl','gfl','gfl','gfl'});
dispatch = struct('IBR2',40,'IBR3',0,'IBR6',0,'IBR8',0);
devices = ibr.build_ieee14_sg_ibr_devices(c,modes,dispatch);
eq = stability.mixed_equilibrium_solve(c,struct('devices',devices), ...
    struct('verbose',false));
testCase.assertTrue(eq.converged,eq.failure_reason);
testCase.TestData.case_data = c;
testCase.TestData.devices = devices;
testCase.TestData.eq = eq;
end

function test_ref_voltage_controls_and_all_kcl(testCase)
eq = testCase.TestData.eq;
testCase.verifyLessThan(eq.residual_norm,1e-6);
testCase.verifyLessThan(eq.physical_kcl_norm,1e-6);
testCase.verifyGreaterThan(eq.rcond,1e-10);
testCase.verifyEqual(eq.vcon_vars,[1 2],'AbsTol',0);
testCase.verifyEqual(eq.vcon_ref,[1.06;0],'AbsTol',0);
testCase.verifyEqual(eq.y0(1:2),[1.06;0],'AbsTol',0);
testCase.verifyEqual(eq.reference.slack_input_names,{'Tm','Efd'});
testCase.verifyEqual(eq.partition.slack_input_unknowns,2,'AbsTol',0);
% The previous literal 57 encoded the retired six-state GFL layout. Derive
% the square all-KCL dimension from the audited current state contract:
% 5 active SG states + 4*7 active WECC GFL states + all 28 KCL rows = 61
% residuals; unknowns replace two REF-voltage coordinates with Tm/Efd.
nb=size(testCase.TestData.case_data.mpc.bus,1);
expected_active=5+4*7;
expected_rows=expected_active+2*nb;
expected_unknowns=expected_active+(2*nb-numel(eq.vcon_vars))+ ...
    eq.partition.slack_input_unknowns;
testCase.verifyEqual(eq.partition.newton_dimension,expected_unknowns,'AbsTol',0);
testCase.verifyEqual(eq.partition.residual_rows,expected_rows,'AbsTol',0);
testCase.verifyEqual(expected_unknowns,expected_rows,'AbsTol',0);
testCase.verifyNotEqual(eq.reference.Tm_solved_pu, ...
    eq.reference.Tm_scheduled_pu, ...
    'Tm is a solved REF output, not silently frozen to the old PF dispatch.');
testCase.verifyNotEqual(eq.reference.Efd_solved_pu, ...
    eq.reference.Efd_scheduled_pu, ...
    'Efd is solved to retain the case REF voltage magnitude.');
end

function test_swing_and_excitation_use_exact_solved_inputs(testCase)
c = testCase.TestData.case_data;
devices = testCase.TestData.devices;
eq = testCase.TestData.eq;
dae = stability.composite_dae(c,devices,struct('load_model','cz_p_cz_q'));
f_exact = dae.dae_f(0,eq.x0,eq.y0,eq.u_eq,eq.equilibrium_context);
g_exact = dae.dae_g(0,eq.x0,eq.y0,dae.Ynet,eq.u_eq,eq.equilibrium_context);
testCase.verifyLessThan(norm(f_exact(eq.active_state_indices),inf),1e-8);
testCase.verifyLessThan(norm(g_exact,inf),1e-6);

% Stale PF-derived Tm/Efd cannot masquerade as the solved mixed operating point.
f_stale = dae.dae_f(0,eq.x0,eq.y0,dae.u0,eq.equilibrium_context);
testCase.verifyGreaterThan(norm(f_stale(eq.active_state_indices),inf),1e-3);

sg = eq.devices(1);
u_sg = eq.u_eq(1:sg.nu);
Pe = sg.electrical_power(0,eq.x0(1:sg.nx),eq.y0,u_sg,eq.equilibrium_context);
testCase.verifyEqual(Pe,u_sg(1),'AbsTol',1e-8, ...
    'At omega=0, the sourced swing equation requires Tm=Te.');
rec = sg.reconstruct(0,eq.x0(1:sg.nx),eq.y0,u_sg,eq.equilibrium_context);
testCase.verifyEqual(rec.Tm,u_sg(1),'AbsTol',0);
testCase.verifyEqual(rec.Efd,u_sg(2),'AbsTol',0);
end

function test_composite_ybus_includes_matpower_bus_shunts(testCase)
c = testCase.TestData.case_data;
devices = testCase.TestData.devices;
dae = stability.composite_dae(c,devices,struct('load_model','cz_p_cz_q'));
mpc = c.mpc;
bus = mpc.bus; br = mpc.branch; nb = size(bus,1);
Y_without_bus_shunt = complex(zeros(nb));
for k = 1:size(br,1)
    if br(k,11)==0, continue; end
    i = find(bus(:,1)==br(k,1),1); j = find(bus(:,1)==br(k,2),1);
    tap = br(k,9); if tap==0, tap=1; end
    a = tap*exp(1i*deg2rad(br(k,10)));
    ys = 1/complex(br(k,3),br(k,4));
    Y_without_bus_shunt(i,i) = Y_without_bus_shunt(i,i) + ...
        ys/(a*conj(a)) + 1i*br(k,5)/2;
    Y_without_bus_shunt(j,j) = Y_without_bus_shunt(j,j) + ys + 1i*br(k,5)/2;
    Y_without_bus_shunt(i,j) = Y_without_bus_shunt(i,j) - ys/conj(a);
    Y_without_bus_shunt(j,i) = Y_without_bus_shunt(j,i) - ys/a;
end
Vpf = dae.pf.bus_voltage(:).*exp(1i*deg2rad(dae.pf.bus_angle_deg(:)));
Sload = (bus(:,3)+1i*bus(:,4))/mpc.baseMVA;
Y_without_bus_shunt = Y_without_bus_shunt + ...
    diag(conj(Sload)./(abs(Vpf).^2+eps));
expected = diag((bus(:,5)+1i*bus(:,6))/mpc.baseMVA);
testCase.verifyEqual(dae.Ynet-Y_without_bus_shunt,expected,'AbsTol',1e-13);
testCase.verifyEqual(imag(expected(9,9)),0.19,'AbsTol',0, ...
    'IEEE14 bus 9 BS=19 MVAr on 100-MVA base.');
end

function test_sg_on_sssa_uses_same_full_kcl_equations(testCase)
c = testCase.TestData.case_data;
eq = testCase.TestData.eq;
opt = struct('full_kcl',true,'u_eq',eq.u_eq, ...
    'event_context',eq.equilibrium_context, ...
    'active_state_indices',eq.active_state_indices);
s = stability.composite_sssa_model(eq.devices,eq.x0,eq.y0,c,opt);
testCase.verifyTrue(s.full_kcl);
testCase.verifyEmpty(s.kcl_rows_replaced);
testCase.verifyLessThan(s.active_f_residual_norm,1e-8);
testCase.verifyLessThan(s.physical_kcl_residual_norm,1e-6);
testCase.verifyGreaterThan(s.gy_rcond,1e-10);
end
