function tests = test_padiyar_ieee14_report_section
%TEST_PADIYAR_IEEE14_REPORT_SECTION Report-only IEEE14/PSAT contract guards.
tests = functiontests(localfunctions);
end

function test_report_scope_and_fresh_generation(testCase)
root = fileparts(fileparts(mfilename('fullpath')));
report_path = fullfile(root,'docs','source','report_padiyar_two_area.tex');
report = fileread(report_path);
start_idx = strfind(report,'\section{IEEE 14-bus cross-validation against PSAT}');
end_idx = strfind(report,'\section{Conclusions}');
verifyNotEmpty(testCase,start_idx);
verifyNotEmpty(testCase,end_idx);
section = report(start_idx(1):end_idx(end)-1);

required_tables = { ...
    'table_ieee14_case_summary.tex', ...
    'table_ieee14_bus_types.tex', ...
    'table_ieee14_bus_data.tex', ...
    'table_ieee14_bus_parameters.tex', ...
    'table_ieee14_generator_data.tex', ...
    'table_ieee14_branch_data.tex', ...
    'table_ieee14_gencost_data.tex', ...
    'table_ieee14_machine_data.tex', ...
    'table_ieee14_scenario_ours_psat.tex', ...
    'table_ieee14_pf_ours_psat.tex', ...
    'table_ieee14_sssa_ours_psat.tex', ...
    'table_ieee14_ts_ours_psat.tex'};
for k=1:numel(required_tables)
    verifyTrue(testCase,contains(section,required_tables{k}));
    verifyEqual(testCase,exist(fullfile(root,'docs','source','figures', ...
        'padiyar_two_area',required_tables{k}),'file'),2);
end

required_figures = { ...
    'ieee14_network.png', ...
    'ieee14_pf_ours_psat.png', ...
    'ieee14_pf_error_ours_psat.png', ...
    'ieee14_sssa_complex_ours_psat.png', ...
    'ieee14_sssa_modes_ours_psat.png', ...
    'ieee14_ts_angle_ours_psat.png', ...
    'ieee14_ts_omega_ours_psat.png', ...
    'ieee14_ts_pe_ours_psat.png', ...
    'ieee14_ts_voltage_ours_psat.png'};
for k=1:numel(required_figures)
    verifyTrue(testCase,contains(section,required_figures{k}));
    verifyEqual(testCase,exist(fullfile(root,'docs','source','figures', ...
        'padiyar_two_area',required_figures{k}),'file'),2);
end

verifyTrue(testCase,contains(section,'Z_f=j10^{-4}'));
verifyTrue(testCase,contains(section,'bus~4'));
verifyTrue(testCase,contains(section,'15~s'));
verifyTrue(testCase,contains(section,'14 bus rows'));
verifyTrue(testCase,contains(section,'five in-service generator rows'));
verifyTrue(testCase,contains(section,'20 in-service branch rows'));
verifyTrue(testCase,contains(section,'System description'));
verifyTrue(testCase,contains(section,'Source data (MATPOWER IEEE 14-bus)'));
verifyTrue(testCase,contains(section,'Bus data and bus types'));
verifyTrue(testCase,contains(section,'Line data'));
verifyTrue(testCase,contains(section,'stored absolute rotor angles'));
verifyTrue(testCase,contains(section,'stored absolute rotor speeds'));
verifyTrue(testCase,contains(section,'Our lines and PSAT cross markers'));
verifyTrue(testCase,contains(section,'direct PSAT--Our'));
verifyFalse(testCase,contains(section,'COI-relative rotor-angle'));
verifyFalse(testCase,contains(section,'COI-relative rotor-speed'));
verifyFalse(testCase,contains(section,'RTS-24'));
verifyFalse(testCase,contains(section,'PGAz'));
verifyFalse(testCase,contains(section,'\begin{equation}'));
verifyFalse(testCase,contains(section,'\begin{align}'));

generator = fileread(fullfile(root,'scripts','reporting', ...
    'generate_padiyar_ieee14_psat_tables.m'));
verifyFalse(testCase,contains(lower(generator),'load('), ...
    'Fresh report generation must not load saved numerical results.');
verifyTrue(testCase,contains(generator,'''fault_bus'',4'));
verifyTrue(testCase,contains(generator,'''Zf'',1i*1e-4'));
verifyTrue(testCase,contains(generator,'''t_end'',15.0'));
verifyTrue(testCase,contains(generator,'pfsolver.powerflow_newton_raphson'));
verifyTrue(testCase,contains(generator,'stability.classical_sssa'));
verifyTrue(testCase,contains(generator,'solve_case(''analysis'',''ts'',''case'',''matpower14'''));
verifyTrue(testCase,contains(generator,'run_psat_case14'));
verifyTrue(testCase,contains(generator,'plot_network(c,scenario'));
verifyTrue(testCase,contains(generator,'plot_ts_generator_pairs'));
verifyFalse(testCase,contains(generator,'coi_relative'));
verifyFalse(testCase,contains(generator,'COI'));
verifyFalse(testCase,contains(generator,'1e6*real'));
verifyTrue(testCase,contains(generator, ...
    'plot_ts_generator_pairs(tg,delta_ours,delta_psat'));
verifyTrue(testCase,contains(generator, ...
    'plot_ts_generator_pairs(tg,omega_ours,omega_psat'));
verifyTrue(testCase,contains(generator,'comparison_marker_indices'));
verifyTrue(testCase,contains(generator,'difference=psat-ours'));
verifyTrue(testCase,contains(generator,'dv4=v4p-v4o'));

ts_table = fileread(fullfile(root,'docs','source','figures', ...
    'padiyar_two_area','table_ieee14_ts_ours_psat.tex'));
verifyFalse(testCase,contains(ts_table,'COI'));
verifyTrue(testCase,contains(ts_table,'Maximum stored rotor-angle magnitude'));
verifyTrue(testCase,contains(ts_table,'Maximum stored rotor-speed magnitude'));

main_generator = fileread(fullfile(root,'scripts','reporting', ...
    'generate_padiyar_two_area_report.m'));
verifyTrue(testCase,contains(main_generator, ...
    'plot_eigs(c,avr,fullfile(outdir,''eigenvalue_comparison.png''))'));
verifyFalse(testCase,contains(main_generator, ...
    'plot_eigs(c,avr,manual,fullfile(outdir,''eigenvalue_comparison.png''))'));
verifyTrue(testCase,contains(main_generator, ...
    'scatter(ax,real(lr),imag(lr),76,''o'''));
verifyTrue(testCase,contains(main_generator, ...
    'scatter(ax,real(la),imag(la),72,''x'''));
verifyTrue(testCase,contains(main_generator, ...
    'Small-Signal Eigenvalue Comparison: Book vs Our AVR'));
verifyTrue(testCase,contains(report, ...
    'computed AVR eigenvalues are crosses'));

psat_driver = fileread(fullfile(root,'scripts','validation','case14', ...
    'run_psat_case14.m'));
verifyTrue(testCase,contains(psat_driver,'runpsat(''pf'')'));
verifyTrue(testCase,contains(psat_driver,'runpsat(''sssa'')'));
verifyTrue(testCase,contains(psat_driver,'runpsat(''td'')'));
verifyTrue(testCase,contains(psat_driver,'ps.sssa_eigenvalues'));
end
