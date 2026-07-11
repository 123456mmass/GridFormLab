function tests=test_padiyar_two_area_reference
tests=functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths;
end

function test_case_manifest(testCase)
c=cases.case_padiyar_two_area_4m_avr();
verifySize(testCase,c.bus_data,[10 12]); verifySize(testCase,c.line_data,[15 7]);
verifyEqual(testCase,[c.machines.units.bus],[1 2 11 12]);
verifyEqual(testCase,[c.machines.units.H],[54 54 63 63]);
verifyEqual(testCase,c.machines.reactances.Xl,0.022,'AbsTol',1e-14);
verifyEqual(testCase,c.machines.reactances.Ra,0.00028,'AbsTol',1e-14);
verifyEqual(testCase,c.machines.reactances.Xd,0.2,'AbsTol',1e-14);
verifyEqual(testCase,c.machines.reactances.Xdp,0.033,'AbsTol',1e-14);
verifyEqual(testCase,c.machines.reactances.Xq,0.19,'AbsTol',1e-14);
verifyEqual(testCase,c.machines.reactances.Xqp,0.061,'AbsTol',1e-14);
verifyEqual(testCase,c.machines.exciter.KA,200,'AbsTol',1e-14);
verifyEqual(testCase,c.machines.exciter.TA,0.02,'AbsTol',1e-14);
verifyFalse(testCase,isfield(c.machines.reactances,'Xdpp'), ...
    'The Padiyar source does not provide subtransient data.');
end

function test_power_flow_reproduces_table_9_2(testCase)
c=cases.case_padiyar_two_area_4m_avr();
r=pfsolver.powerflow_newton_raphson(c,struct('verbose',false,'plot_results',false, ...
    'enforce_q_limits',false,'tolerance',1e-11));
verifyTrue(testCase,r.converged); [ok,ix]=ismember(c.operating_point.printed_bus_ids,r.external_bus_ids);
verifyTrue(testCase,all(ok));
verifyLessThan(testCase,max(abs(r.bus_voltage(ix)-c.operating_point.printed_V)),1e-4);
verifyLessThan(testCase,max(abs(r.bus_angle_deg(ix)-c.operating_point.printed_angle_deg)),1e-4);
verifyLessThan(testCase,max(abs(r.P_generation(ix)-c.operating_point.printed_Pg)),1e-4);
verifyLessThan(testCase,max(abs(r.Q_generation(ix)-c.operating_point.printed_Qg)),1e-4);
end

function test_avr_dae_equilibrium_and_order(testCase)
d=stability.padiyar_model11_dae([],struct('excitation','avr'));
verifyEqual(testCase,d.ns,5); verifyEqual(testCase,numel(d.x0),20);
verifyLessThan(testCase,d.initial_residual_f,1e-10);
verifyLessThan(testCase,d.initial_residual_g,1e-10);
verifyEqual(testCase,d.electrical_power(d.x0,d.y0),d.init.Pm,'AbsTol',1e-10);
end

function test_manual_dae_equilibrium_and_order(testCase)
d=stability.padiyar_model11_dae([],struct('excitation','manual'));
verifyEqual(testCase,d.ns,4); verifyEqual(testCase,numel(d.x0),16);
verifyLessThan(testCase,d.initial_residual,1e-10);
end

function test_table_9_5_secondary_crosscheck(testCase)
c=cases.case_padiyar_two_area_4m_avr();
r=stability.padiyar_model11_ssa(c,struct('excitation','avr','fd_eps',1e-6));
ref=c.reference.table95_eigenvalues(:);
% The printed near-zero pair is explicitly attributed by Padiyar to load-flow
% and numerical error. Compare the 18 nonzero physical roots one-to-one.
ref=ref(abs(ref)>0.01); got=r.eigenvalues(abs(r.eigenvalues)>0.01);
verifyEqual(testCase,numel(got),numel(ref));
err=greedy_error(got,ref);
verifyLessThan(testCase,max(err),0.06, ...
    'Published Table 9.5 is a secondary cross-check, never a fitted target.');
end

function test_reference_eigenvalues_do_not_drive_sssa(testCase)
% Falsification test: corrupting the published comparison data must not alter
% the computed state matrix or eigenvalues.
c=cases.case_padiyar_two_area_4m_avr();
r1=stability.padiyar_model11_ssa(c,struct('excitation','avr','fd_eps',1e-6));
c.reference.table95_eigenvalues=(101:120).'+1i*(201:220).';
r2=stability.padiyar_model11_ssa(c,struct('excitation','avr','fd_eps',1e-6));
verifyEqual(testCase,r2.Afull,r1.Afull,'AbsTol',1e-12);
verifyEqual(testCase,sort(r2.eigenvalues),sort(r1.eigenvalues),'AbsTol',1e-12);
end

function test_no_fault_ts_equilibrium(testCase)
for excitation={'manual','avr'}
    r=stability.ts_simulate_padiyar_model11([],struct('excitation',excitation{1}, ...
        'fault_enabled',false,'t_end',1,'dt',0.01));
    verifyEqual(testCase,r.nonconverged_step_count,0);
    verifyLessThan(testCase,r.initial_dae_residual,1e-10);
    verifyLessThan(testCase,max(abs(r.delta-r.delta(1,:)),[],'all'),1e-10);
    verifyLessThan(testCase,max(abs(r.omega-r.omega(1,:)),[],'all'),1e-10);
    verifyLessThan(testCase,max(abs(r.Vbus-r.Vbus(1,:)),[],'all'),1e-10);
  end
end

function test_project_fault_scenario_converges(testCase)
for excitation={'manual','avr'}
    r=stability.ts_simulate_padiyar_model11([],struct('excitation',excitation{1}, ...
        'fault_enabled',true,'fault_bus',3,'Zf',1i*0.5,'t_fault',1, ...
        't_clear',1.1,'t_end',2,'dt',0.005));
    verifyEqual(testCase,r.nonconverged_step_count,0);
    verifyTrue(testCase,all(isfinite(r.delta),'all'));
    verifyTrue(testCase,all(isfinite(r.Vbus),'all'));
  end
end

function err=greedy_error(got,ref)
got=got(:); ref=ref(:); used=false(size(got)); err=zeros(size(ref));
for k=1:numel(ref)
    d=abs(got-ref(k)); d(used)=inf; [err(k),j]=min(d); used(j)=true;
end
end
