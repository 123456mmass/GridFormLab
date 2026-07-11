function tests = test_matpower6_case14()
%TEST_MATPOWER6_CASE14 Validate imported MATPOWER 6.0 case14 data.

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function test_case14_data_import(testCase)
    c = cases.case_matpower6_case14();
    testCase.verifyEqual(c.base_values.S_base_MVA, 100);
    testCase.verifySize(c.bus_data, [14 12]);
    testCase.verifySize(c.line_data, [20 7]);
    testCase.verifySize(c.mpc.gen, [5 21]);
    testCase.verifyEqual(c.mpc.bus(1,2), 3, 'MATPOWER slack bus type should be preserved in raw mpc.');
    testCase.verifyEqual(c.bus_data(1,2), 1, 'Project slack bus type should be converted to 1.');
end

function test_case14_powerflow_matches_matpower_reference(testCase)
    c = cases.case_matpower6_case14();
    r = pfsolver.powerflow_newton_raphson(c, struct('verbose', false, 'plot_results', false, ...
        'max_iter', 50, 'tolerance', 1e-10, 'enforce_q_limits', false));
    testCase.verifyTrue(r.converged, 'Imported MATPOWER6 case14 should converge with in-house NR solver.');
    ref = c.reference_solution;
    % MATPOWER case14 stores a rounded solved profile (about 3 decimals for
    % voltage and 2 decimals for angle). Allow the small published-data
    % rounding/convention difference while still checking the imported case.
    testCase.verifyLessThan(max(abs(r.bus_voltage - ref.bus_voltage)), 2e-3, ...
        'Voltage magnitudes should match MATPOWER case14 profile within published rounding.');
    testCase.verifyLessThan(max(abs(r.bus_angle_deg - ref.bus_angle_deg)), 0.05, ...
        'Voltage angles should match MATPOWER case14 solved profile.');
end

function test_import_matches_existing_project_ieee14_conversion(testCase)
    c_new = cases.case_matpower6_case14();
    c_old = cases.case_ieee14bus();
    r_new = pfsolver.powerflow_newton_raphson(c_new, struct('verbose', false, 'plot_results', false, ...
        'max_iter', 50, 'tolerance', 1e-10, 'enforce_q_limits', false));
    r_old = pfsolver.powerflow_newton_raphson(c_old, struct('verbose', false, 'plot_results', false, ...
        'max_iter', 50, 'tolerance', 1e-10, 'enforce_q_limits', false));
    testCase.verifyTrue(r_new.converged && r_old.converged);
    testCase.verifyEqual(r_new.bus_voltage, r_old.bus_voltage, 'AbsTol', 1e-10);
    testCase.verifyEqual(r_new.bus_angle_deg, r_old.bus_angle_deg, 'AbsTol', 1e-8);
end
