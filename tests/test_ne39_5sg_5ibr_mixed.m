function tests = test_ne39_5sg_5ibr_mixed()
%TEST_NE39_5SG_5IBR_MIXED ตรวจ equation equilibrium ของ New England 39 แบบผสม.
% ตรวจ operating point, ทุกแถว physical KCL และ classical controls ของ SG31
% แยก residual ของสมการจาก physical capability ซึ่งยังไม่รับรองเมื่อ Pmax unknown
% ไม่ผ่อน tolerance และไม่ถือว่า equation solution เป็นใบอนุมัติ switching.
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
tc.TestData.s = s;
tc.TestData.devices = devices;
tc.TestData.eq = eq;
end

function test_scenario_builds_ten_devices_in_order(tc)
s = tc.TestData.s;
tc.verifyEqual(numel(s.resources),10);
tc.verifyEqual(cellstr(string({s.resources.resource_id})), ...
    {'SG31','SG32','SG35','SG38','SG39','IBR30','IBR33','IBR34','IBR36','IBR37'});
end

function test_equation_equilibrium_with_uncertified_capability(tc)
eq = tc.TestData.eq;
tc.verifyFalse(eq.converged); % TAMU ไม่ระบุ physical active capability
tc.verifyTrue(contains(eq.failure_reason,'operating limit'));
tc.verifyLessThan(eq.residual_norm,1e-8);
tc.verifyLessThan(eq.physical_kcl_norm,1e-8);
tc.verifyGreaterThan(eq.rcond,1e-10);
end

function test_reference_is_the_slack_machine(tc)
eq = tc.TestData.eq;
tc.verifyEqual(eq.reference.device_id,'SG31');
tc.verifyEqual(eq.reference.control_layout,'classical_pm_emag');
tc.verifyEqual(eq.reference.slack_input_names,{'Pm','Emag'});
tc.verifyEqual(eq.reference.Pm_solved_pu, eq.u_eq(1),'AbsTol',1e-12);
end

function test_device_terminal_powers_match_the_case_schedule(tc)
eq = tc.TestData.eq; s = tc.TestData.s;
V = complex(eq.y0(1:2:end), eq.y0(2:2:end));
expP = containers.Map(); expQ = containers.Map();
for k = 1:numel(s.resources)
    r = s.resources(k); b = r.bus_id;
    expP(r.resource_id) = s.case_data.bus_data(b,5)*100;
    if strcmp(r.resource_type,'ibr')
        expQ(r.resource_id) = s.case_data.bus_data(b,6)*100;
    end
end
xo = 0; uo = 0;
for k = 1:numel(eq.devices)
    d = eq.devices(k);
    I = d.current_injection(0, eq.x0(xo+(1:d.nx)), eq.y0, ...
        eq.u_eq(uo+(1:d.nu)), eq.equilibrium_context);
    S = V(d.bus_position)*conj(I);
    tc.verifyEqual(real(S)*100, expP(d.device_id),'AbsTol',3e-2, ...
        sprintf('%s active power',d.device_id));
    if isKey(expQ,d.device_id)
        tc.verifyEqual(imag(S)*100, expQ(d.device_id),'AbsTol',1e-4, ...
            sprintf('%s reactive power',d.device_id));
    end
    xo = xo + d.nx; uo = uo + d.nu;
end
end

function test_unknown_active_limits_are_not_certified(tc)
eq = tc.TestData.eq;
names = fieldnames(eq.limit_checks.devices);
tc.verifyEqual(numel(names),10);
for k = 1:numel(names)
    L = eq.limit_checks.devices.(names{k});
    tc.verifyTrue(L.within_transient_current_limit);
    tc.verifyFalse(L.within_active_power_limit);
    tc.verifyFalse(L.within_limits);
end
end

function test_full_kcl_sssa_builds(tc)
eq = tc.TestData.eq; s = tc.TestData.s;
s2 = stability.composite_sssa_model(eq.devices, eq.x0, eq.y0, s.case_data, ...
    struct('full_kcl',true,'u_eq',eq.u_eq,'event_context',eq.equilibrium_context, ...
    'active_state_indices',eq.active_state_indices,'fd_eps',3e-6, ...
    'reference_device_index',eq.reference.device_index));
tc.verifyGreaterThanOrEqual(size(s2.A,1), 1);
tc.verifyEqual(size(s2.A,1), size(s2.A,2));
tc.verifyTrue(all(isfinite(s2.eigenvalues)));
tc.verifyLessThan(s2.physical_kcl_residual_norm,1e-6);
end
