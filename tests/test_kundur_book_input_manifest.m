function tests = test_kundur_book_input_manifest()
%TEST_KUNDUR_BOOK_INPUT_MANIFEST Freeze the scanned Example 12.6 inputs.
tests = functiontests(localfunctions);
end

function test_printed_machine_and_base_data(testCase)
c = cases.kundur_ex126_book_case();
verifyEqual(testCase,c.base_values,struct('S_base_MVA',100,'V_base_kV',230,'frequency_Hz',60));
verifyEqual(testCase,c.machines.base.S_MVA,900);
verifyEqual(testCase,c.machines.base.V_kV,20);
verifyEqual(testCase,c.machines.reactances,struct( ...
    'Xd',1.8,'Xq',1.7,'Xl',0.2,'Xdp',0.3,'Xqp',0.55, ...
    'Xdpp',0.25,'Xqpp',0.25,'Ra',0.0025));
verifyEqual(testCase,c.machines.time_constants,struct( ...
    'Tpd0',8.0,'Tppd0',0.03,'Tpq0',0.4,'Tppq0',0.05));
verifyEqual(testCase,[c.machines.units.H],[6.5,6.5,6.175,6.175]);
verifyEqual(testCase,[c.machines.units.D],[0,0,0,0]);
verifyEqual(testCase,c.saturation,struct('Asat',0.015,'Bsat',9.6,'PsiT1',0.9));
verifyEqual(testCase,c.operating_point.load_model,'cc_p_cz_q');
verifyTrue(testCase,c.operating_point.manual_excitation);
verifyTrue(testCase,c.operating_point.constant_tm);
end

function test_topology_and_printed_loads(testCase)
c = cases.kundur_ex126_book_case();
verifySize(testCase,c.bus_data,[11,10]);
verifySize(testCase,c.line_data,[12,5]);
verifyEqual(testCase,c.bus_data(7,[7,8,10]),[9.67,1.00,2.00]);
verifyEqual(testCase,c.bus_data(9,[7,8,10]),[17.67,1.00,3.50]);
xt = 0.15*(100/900);
verifyEqual(testCase,c.line_data(1:4,4).',[xt,xt,xt,xt],'AbsTol',eps);
verifyEqual(testCase,c.line_data(7,:),c.line_data(8,:));
verifyEqual(testCase,c.line_data(9,:),c.line_data(10,:));
verifyEqual(testCase,c.line_data(:,1:2), ...
    [1 5;2 6;3 11;4 10;5 6;6 7;7 8;7 8;8 9;8 9;9 10;10 11]);
end

function test_table_e123_target_transcription(testCase)
% Target only: this list must never be used to construct a model matrix.
target = [ ...
    -0.00076+1i*0.0022; -0.00076-1i*0.0022; -0.096; ...
    -0.111+1i*3.43; -0.111-1i*3.43; -0.117; -0.265; -0.276; ...
    -0.492+1i*6.82; -0.492-1i*6.82; -0.506+1i*7.02; -0.506-1i*7.02; ...
    -3.428; -4.139; -5.287; -5.303; -31.03; -32.45; -34.07; -35.53; ...
    -37.89+1i*0.142; -37.89-1i*0.142; -38.01+1i*0.038; -38.01-1i*0.038];
verifyEqual(testCase,numel(target),24);
verifyEqual(testCase,target(1),-0.76e-3+1i*0.22e-2);
verifyEqual(testCase,target(21),-37.89+1i*0.142);
verifyEqual(testCase,target(23),-38.01+1i*0.038);
end
