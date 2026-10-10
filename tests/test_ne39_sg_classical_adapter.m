function tests = test_ne39_sg_classical_adapter()
%TEST_NE39_SG_CLASSICAL_ADAPTER  Classical adapter vs the classical_dae oracle.
%   Builds the FULL ten-machine New England case (cases.case_ne39) as ten
%   stability.sg_classical_device instances, solves the coupled mixed-equilibrium
%   and compares, machine by machine, against stability.classical_dae on the SAME
%   network / power flow / load settings.  This is the independent oracle the plan
%   requires BEFORE any stability claim is made on the mixed NE39 case: if the
%   adapter did not reproduce the case's own classical model exactly, the mixed
%   result would be measuring the adapter, not the system.  Nothing is relaxed:
%   the comparisons are exact (tolerances 1e-8 pu / 1e-8 rad).
tests = functiontests(localfunctions);
end

function setupOnce(tc)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
c = cases.case_ne39();
devs = [];
for b = 30:39
    bp = find(c.bus_data(:,1)==b,1);
    devs = [devs, stability.sg_classical_device(c, sprintf('SG%d',b), b, bp, ...
        c.bus_data(:,1)', c.bus_data(bp,3), struct())]; %#ok<AGROW>
end
eq = stability.mixed_equilibrium_solve(c, struct('devices',devs), ...
    struct('verbose',false));
oracle = stability.classical_dae(c, struct('pm_mode','balanced','verbose',false));
tc.TestData.c = c;
tc.TestData.devs = devs;
tc.TestData.eq = eq;
tc.TestData.oracle = oracle;
end

function test_equilibrium_converges(tc)
eq = tc.TestData.eq;
tc.verifyTrue(eq.converged, eq.failure_reason);
tc.verifyLessThan(eq.residual_norm,1e-8);
tc.verifyLessThan(eq.physical_kcl_norm,1e-8);
end

function test_adapter_angles_match_classical_dae(tc)
eq = tc.TestData.eq; dae = tc.TestData.oracle; devs = tc.TestData.devs;
ng = numel(dae.gen_buses);
delta = zeros(ng,1); xo = 0;
for k = 1:ng
    delta(k) = eq.x0(xo+1); xo = xo + devs(k).nx;
end
tc.verifyEqual(delta, dae.x0(1:ng),'AbsTol',1e-8);
end

function test_adapter_speeds_are_nominal_at_equilibrium(tc)
eq = tc.TestData.eq; devs = tc.TestData.devs;
xo = 0;
for k = 1:numel(devs)
    tc.verifyEqual(eq.x0(xo+2),1.0,'AbsTol',1e-10);
    xo = xo + devs(k).nx;
end
end

function test_adapter_electrical_power_matches_oracle_pm(tc)
eq = tc.TestData.eq; dae = tc.TestData.oracle; devs = tc.TestData.devs;
V = complex(eq.y0(1:2:end), eq.y0(2:2:end));
ng = numel(dae.gen_buses);
xo = 0; uo = 0; Pe = zeros(ng,1);
for k = 1:ng
    d = devs(k);
    I = d.current_injection(0, eq.x0(xo+(1:d.nx)), eq.y0, ...
        eq.u_eq(uo+(1:d.nu)), eq.equilibrium_context);
    Pe(k) = real(V(d.bus_position)*conj(I));
    xo = xo + d.nx; uo = uo + d.nu;
end
tc.verifyEqual(Pe, dae.Pm,'AbsTol',1e-8);
end

function test_adapter_matches_network_voltage_profile(tc)
eq = tc.TestData.eq; dae = tc.TestData.oracle;
V_mixed  = complex(eq.y0(1:2:end), eq.y0(2:2:end));
V_oracle = complex(dae.y0(1:2:end), dae.y0(2:2:end));
tc.verifyEqual(V_mixed, V_oracle,'AbsTol',1e-8);
end

function test_adapter_rhs_is_zero_at_equilibrium(tc)
eq = tc.TestData.eq; devs = tc.TestData.devs;
xo = 0; uo = 0;
for k = 1:numel(devs)
    d = devs(k);
    f = d.f(0, eq.x0(xo+(1:d.nx)), eq.y0, eq.u_eq(uo+(1:d.nu)), eq.equilibrium_context);
    tc.verifyLessThan(norm(f,inf),1e-8, d.device_id);
    xo = xo + d.nx; uo = uo + d.nu;
end
end

function test_reference_layout_is_classical_not_emf6(tc)
r = tc.TestData.eq.reference;
tc.verifyEqual(r.control_layout,'classical_pm_emag');
tc.verifyEqual(r.slack_input_names,{'Pm','Emag'});
tc.verifyTrue(isfinite(r.Pm_solved_pu));
tc.verifyTrue(isfinite(r.Emag_solved_pu));
tc.verifyTrue(isnan(r.Tm_solved_pu));    % |E| is NOT relabelled as EMF6 Efd
tc.verifyTrue(isnan(r.Efd_solved_pu));
end

function test_full_kcl_sssa_builds_with_finite_eigenvalues(tc)
eq = tc.TestData.eq; c = tc.TestData.c;
s = stability.composite_sssa_model(eq.devices, eq.x0, eq.y0, c, ...
    struct('full_kcl',true,'u_eq',eq.u_eq,'event_context',eq.equilibrium_context, ...
    'active_state_indices',eq.active_state_indices,'fd_eps',3e-6, ...
    'reference_device_index',eq.reference.device_index));
tc.verifyEqual(size(s.A,1),20);   % 2 states x 10 machines
tc.verifyTrue(all(isfinite(s.eigenvalues)));
tc.verifyLessThan(s.active_f_residual_norm,1e-8);
tc.verifyLessThan(s.physical_kcl_residual_norm,1e-6);
end
