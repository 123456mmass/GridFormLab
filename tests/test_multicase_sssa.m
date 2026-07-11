function tests = test_multicase_sssa()
tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function test_kundur_default_uses_operational_emf6(testCase)
% The Kundur 12.6 default SSSA must use the operational EMF6 model -- the
% single sixth-order equation set shared with TS (stability.emf6_dae) --
% built with the in-house Newton solver and no fsolve/optimoptions.
% Kundur Table E12.3 is never used as an acceptance target here.
r=stability.multicase_sssa(cases.kundur_ex126_book_case());
verifyEqual(testCase,r.metadata.plugin,'operational_emf_sixth_order');
verifyEqual(testCase,r.metadata.engine,'stability.multimachine_ssa');
verifyEqual(testCase,numel(r.eigenvalues),24);
verifyTrue(testCase,all(isfinite(r.eigenvalues)));
verifyLessThan(testCase,norm([r.debug_residual_f;r.debug_residual_g],inf),1e-8);
verifyLessThan(testCase,r.angle_shift_residual,1e-6);
% No fsolve in the equilibrium path.
if isfield(r,'equilibrium_solver')
    verifyNotEqual(testCase,r.equilibrium_solver,'fsolve');
end
% Structural zero-mode: a common rotor rotation is a null direction of the
% autonomous DAE (no infinite bus / no governor).
A=r.Afull; vangle=zeros(size(A,1),1); vangle(1:6:end)=1;
verifyLessThan(testCase,norm(A*vangle),1e-7);
end

function test_sauer_pai_published_case_stays_within_half_percent(testCase)
r=stability.multicase_sssa(cases.sauer_pai_ex83_case());
ref=cases.sauer_pai_reference_catalog().example_8_3_table_8_1.eigenvalues;
verifyLessThan(testCase,max_component_error(r.eigenvalues,ref),0.005);
end

function test_synthetic_case_is_parameter_driven(testCase)
c=cases.synthetic_sauer_pai_case(5);
r1=stability.multicase_sssa(c);
c.H(1)=1.01*c.H(1);
r2=stability.multicase_sssa(c);
verifyEqual(testCase,numel(r1.eigenvalues),35);
verifyGreaterThan(testCase,norm(r1.Afull-r2.Afull,'fro'),1e-8);
end

function e=max_component_error(lam,ref)
used=false(numel(ref),1); e=0;
for k=1:numel(lam)
    d=abs(lam(k)-ref); d(used)=inf; [~,j]=min(d); used(j)=true;
    er=abs(real(lam(k))-real(ref(j))); ei=abs(imag(lam(k))-imag(ref(j)));
    if abs(real(ref(j)))>1e-6, er=er/abs(real(ref(j))); end
    if abs(imag(ref(j)))>1e-6, ei=ei/abs(imag(ref(j))); end
    e=max(e,max(er,ei));
end
end
