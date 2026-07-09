function tests = test_case14_pgaz_reference()
%TEST_CASE14_PGAZ_REFERENCE Compare imported case14 PF with PGAz report values.

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function test_case14_powerflow_matches_pgaz_report(testCase)
    c = cases.case_matpower6_case14();
    r = pfsolver.powerflow_newton_raphson(c, struct('verbose', false, 'plot_results', false, ...
        'max_iter', 50, 'tolerance', 1e-10, 'enforce_q_limits', false));
    testCase.verifyTrue(r.converged);

    % Values copied from PGAz v1.1.1 report for case14_mp_test.m, 09-Jul-2026.
    V_pgaz = [1.060;1.045;1.010;1.018;1.020;1.070;1.062;1.090;1.056;1.051;1.057;1.055;1.050;1.036];
    A_pgaz = [0.000;-4.983;-12.725;-10.313;-8.774;-14.221;-13.360;-13.360;-14.939;-15.097;-14.791;-15.076;-15.156;-16.034];
    Pg_pgaz = 272.393;
    Qg_pgaz = 82.438;
    Ploss_pgaz = 13.393;
    Qloss_pgaz = 30.122;

    testCase.verifyLessThan(max(abs(r.bus_voltage - V_pgaz)), 7e-4, 'Bus voltage mismatch vs PGAz report.');
    testCase.verifyLessThan(max(abs(r.bus_angle_deg - A_pgaz)), 7e-4, 'Bus angle mismatch vs PGAz report.');
    testCase.verifyEqual(r.P_total_gen*100, Pg_pgaz, 'AbsTol', 5e-4);
    testCase.verifyEqual(r.Q_total_gen*100, Qg_pgaz, 'AbsTol', 5e-4);
    testCase.verifyEqual(r.P_loss_total*100, Ploss_pgaz, 'AbsTol', 5e-4);
    testCase.verifyEqual(r.Q_loss_total*100, Qloss_pgaz, 'AbsTol', 5e-4);
end
