function tests = test_ibr_gfl_model
% Independent falsification tests for the WECC REGC_A + REEC_A GFL model.
% The former test file asserted the Ding-derived Kps/Kis equations.  That
% mathematical contract was proven unsuitable for production because the
% cited source contains no numerical Kps/Kis values.  The approved model
% replacement uses the WECC 2014 specification and official REEC_A example;
% the hand calculations below are independent of the implementation helpers.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(mfilename('fullpath')));
addpath(root,'-begin');
testCase.TestData.root = root;
testCase.addTeardown(@() rmpath(root));
end

function test_wrapper_routes_to_wecc_model(testCase)
d = make_dev(struct(),0.4,0.1);
testCase.verifyEqual(d.provenance.model,'WECC_REGC_A_REEC_A');
testCase.verifyEqual(d.nx,7,'AbsTol',0);
testCase.verifyEqual(d.state_names, ...
    {'Vt_f','P_f','Iq_cmd_f','Pord','Vlvpl_f','Ip_reg','Iq_reg'});
testCase.verifyEqual(d.device_type,'ibr_gfl_wecc_regca_reeca');
end

function test_equilibrium_identity_system_base(testCase)
d = make_dev(struct('Mbase',140),0.4,0.1);
y = y_for(1.04*exp(1i*0.17));
xeq = d.equilibrium_initialize(y(3)+1i*y(4),0.4,0.1,struct());
dx = d.f(0,xeq,y,[0.4;0.1],struct());
I = d.current_injection(0,xeq,y,[0.4;0.1],struct());
S = (y(3)+1i*y(4))*conj(I);
testCase.verifyEqual(dx,zeros(7,1),'AbsTol',2e-13);
testCase.verifyEqual(real(S),0.4,'AbsTol',2e-13);
testCase.verifyEqual(imag(S),0.1,'AbsTol',2e-13);
end

function test_kappa_base_conversion(testCase)
d = make_dev(struct('Mbase',140),0.4,0.0);
r = reconstruct(d,d.x0,y_for(1.04),d.u0);
testCase.verifyEqual(r.kappa,100/140,'AbsTol',1e-15);
testCase.verifyEqual(d.x0(4),(100/140)*0.4,'AbsTol',1e-15);
testCase.verifyEqual(r.Pe,0.4,'AbsTol',2e-14);
end

function test_rotation_invariance(testCase)
d1 = make_dev(struct(),0.4,0.1);
d2 = ibr.gfl_model("T",2,2,[1 2],1.04*exp(1i*0.63),struct(),0.4,0.1);
y1 = y_for(1.04*exp(1i*0.13));
y2 = y_for(1.04*exp(1i*0.63));
I1 = d1.current_injection(0,d1.equilibrium_initialize(y1(3)+1i*y1(4),0.4,0.1,struct()),y1,d1.u0,struct());
I2 = d2.current_injection(0,d2.equilibrium_initialize(y2(3)+1i*y2(4),0.4,0.1,struct()),y2,d2.u0,struct());
testCase.verifyEqual(I2,I1*exp(1i*0.50),'AbsTol',2e-13);
end

function test_p_priority_current_oracle(testCase)
d = make_dev(struct('PQFlag',1),0.4,0.0);
x = d.x0; x(1)=1.0; x(4)=0.8;
r = reconstruct(d,x,y_for(1.0),[0.8;0.8]);
testCase.verifyEqual(r.Ipcmd,0.8,'AbsTol',1e-14);
testCase.verifyEqual(r.Iqcmd,sqrt(1-0.8^2),'AbsTol',1e-14);
testCase.verifyLessThanOrEqual(hypot(r.Ipcmd,r.Iqcmd),1+1e-14);
end

function test_q_priority_current_oracle(testCase)
d = make_dev(struct('PQFlag',0),0.4,0.0);
x = d.x0; x(1)=1.0; x(4)=0.8;
r = reconstruct(d,x,y_for(1.0),[0.8;0.8]);
testCase.verifyEqual(r.Iqcmd,0.8,'AbsTol',1e-14);
testCase.verifyEqual(r.Ipcmd,sqrt(1-0.8^2),'AbsTol',1e-14);
end

function test_voltage_dip_reactive_injection(testCase)
d = make_dev(struct('Vref0',1.0),0.4,0.0);
x = d.x0; x(1)=0.80;
r = reconstruct(d,x,y_for(0.80),[0.4;0.0]);
% error=1-.8=.2; deadband removes .1; Kqv=2 -> +.2 pu.
testCase.verifyEqual(r.Iqcmd,0.20,'AbsTol',2e-14);
testCase.verifyTrue(r.voltage_dip);
end

function test_lvpl_piecewise_oracle(testCase)
d = make_dev(struct(),0.4,0.0);
x = d.x0; x(1)=0.65; x(4)=0.8; x(5)=0.65; x(6)=0.8;
dx = d.f(0,x,y_for(0.65),[0.8;0],struct());
lvpl = 1.22*(0.65-0.40)/(0.90-0.40);
testCase.verifyEqual(dx(6),(lvpl-0.8)/0.02,'AbsTol',2e-13);
end

function test_low_voltage_gain_zero(testCase)
d = make_dev(struct(),0.4,0.0);
x = d.x0; x(6)=0.8;
I = d.current_injection(0,x,y_for(0.40),d.u0,struct());
% Active path is zero at lvpnt0; Q is also zero in this fixture.
testCase.verifyEqual(I,0i,'AbsTol',1e-14);
end

function test_high_voltage_reactive_management(testCase)
d = make_dev(struct(),0.4,0.0);
x = d.x0; x(7)=0.20;
r = reconstruct(d,x,y_for(1.30),d.u0);
% Iq_out=.2-.7*(1.3-1.2)=.13, above Iolim=-1.3.
testCase.verifyEqual(r.Qe,1.30*0.13,'AbsTol',2e-14);
end

function test_bad_mapping_fails_closed(testCase)
testCase.verifyError(@() ibr.gfl_model("T",2,1,[1 2],1,struct(),0.4,0), ...
    'ibr:wecc_regca_reeca_model:busMappingMismatch');
end

function test_bad_parameter_order_fails_closed(testCase)
testCase.verifyError(@() make_dev(struct('Zerox',0.95,'Brkpt',0.9),0.4,0), ...
    'ibr:wecc_regca_reeca_model:badParam');
end

function test_equilibrium_current_limit_fails_closed(testCase)
d = make_dev(struct(),0.4,0.0);
testCase.verifyError(@() d.equilibrium_initialize(1.0,0.9,0.9,struct()), ...
    'ibr:wecc_regca_reeca_model:equilibriumCurrentLimit');
end

function test_no_unsourced_ding_gains_on_path(testCase)
root = fileparts(fileparts(mfilename('fullpath')));
src = fileread(fullfile(root,'+ibr','wecc_regca_reeca_model.m'));
wrapper = fileread(fullfile(root,'+ibr','gfl_model.m'));
testCase.verifyFalse(contains(src,'Kps'));
testCase.verifyFalse(contains(src,'Kis'));
testCase.verifyTrue(contains(wrapper,'wecc_regca_reeca_model'));
end

function test_provenance_and_scr_applicability(testCase)
d = make_dev(struct(),0.4,0.0);
testCase.verifyTrue(contains(d.provenance.source,'WECC'));
testCase.verifyTrue(contains(d.provenance.applicability,'SCR<=3'));
testCase.verifyEqual(d.provenance.readiness,'SOURCE_IMPLEMENTED_PENDING_INTEGRATION_GATES');
end

function d = make_dev(params,P,Q)
d = ibr.gfl_model("T",2,2,[1 2],1.04*exp(1i*0.13),params,P,Q);
end

function y = y_for(V)
y = [1;0;real(V);imag(V)];
end

function r = reconstruct(d,x,y,u)
r = d.reconstruct(0,x,y,u,struct());
end
