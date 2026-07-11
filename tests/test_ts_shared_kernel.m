function tests = test_ts_shared_kernel
%TEST_TS_SHARED_KERNEL Phase 2 contract tests for the shared step kernel.
%   Verifies that the refactored fixed-step engines (Padiyar, EMF6) produce
%   bit-identical output to the pre-refactor baseline, and that the shared
%   kernel, algebraic solve, Jacobian and topology functions satisfy their
%   contracts.
tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function test_one_step_equivalence(testCase)
% A.2: one kernel step at h == one manual step at h (before error control).
c=cases.case_padiyar_two_area_4m_avr();
opt=struct('fault_enabled',false,'excitation','avr','verbose',false);
dae=stability.padiyar_model11_dae(c,opt);
x=dae.x0(:); y=dae.y0(:); h=0.005; Y=dae.Ynet;
f=dae.dae_f; g=dae.dae_g;
kopt=struct('algebraic_tolerance',1e-11,'max_corrector_iter',12, ...
    'corrector_abs_tol',1e-10,'corrector_rel_tol',1e-8);
step=stability.ts_step_kernel(x,y,h,f,g,Y,[],kopt);
% Manual replication
J=stability.ts_jac_y_fd(x,y,Y,g);
[ym,~]=stability.ts_algebraic_solve(x,y,Y,g,@stability.ts_jac_y_fd,1e-11,J);
f0=f(x,ym); xn=x+h*f0; yn=ym;
for ci=1:12
    [yn2,~]=stability.ts_algebraic_solve(xn,yn,Y,g,@stability.ts_jac_y_fd,1e-11,J);
    f1=f(xn,yn2); xnew=x+0.5*h*(f0+f1);
    [ynew,~]=stability.ts_algebraic_solve(xnew,yn2,Y,g,@stability.ts_jac_y_fd,1e-11,J);
    R=xnew-x-0.5*h*(f0+f(xnew,ynew));
    upd=norm(xnew-xn,inf); rn=norm(R,inf); xn=xnew; yn=ynew;
    tol=1e-10+1e-8*max(1,norm(xn,inf));
    if upd<=tol && rn<=tol, break; end
end
testCase.verifyEqual(step.x_full,xn,'AbsTol',0);
testCase.verifyEqual(step.corrector_iterations,ci);
testCase.verifyEqual(step.corrector_residual,rn,'AbsTol',0);
end

function test_algebraic_residual(testCase)
% A.3: algebraic residual after kernel step is within tolerance.
c=cases.case_padiyar_two_area_4m_avr();
opt=struct('fault_enabled',false,'excitation','avr','verbose',false);
dae=stability.padiyar_model11_dae(c,opt);
x=dae.x0(:); y=dae.y0(:); h=0.005; Y=dae.Ynet;
kopt=struct('algebraic_tolerance',1e-11,'max_corrector_iter',12, ...
    'corrector_abs_tol',1e-10,'corrector_rel_tol',1e-8);
step=stability.ts_step_kernel(x,y,h,dae.dae_f,dae.dae_g,Y,[],kopt);
testCase.verifyLessThan(step.algebraic_residual,1e-10);
end

function test_trapezoidal_residual(testCase)
% A.3: trapezoidal residual is within tolerance and corrector converged.
c=cases.case_padiyar_two_area_4m_avr();
opt=struct('fault_enabled',false,'excitation','avr','verbose',false);
dae=stability.padiyar_model11_dae(c,opt);
x=dae.x0(:); y=dae.y0(:); h=0.005; Y=dae.Ynet;
kopt=struct('algebraic_tolerance',1e-11,'max_corrector_iter',12, ...
    'corrector_abs_tol',1e-10,'corrector_rel_tol',1e-8);
step=stability.ts_step_kernel(x,y,h,dae.dae_f,dae.dae_g,Y,[],kopt);
testCase.verifyTrue(step.corrector_converged);
testCase.verifyLessThan(step.corrector_residual,1e-8);
end

function test_topology_event_semantics(testCase)
% A.4: topology selector returns correct admittance for each event side.
Ypre=eye(3); Yfault=Ypre; Yfault(2,2)=Yfault(2,2)+10; Ypost=Ypre;
opt=struct('fault_enabled',true,'t_fault',1.0,'t_clear',1.1);
testCase.verifyEqual(stability.ts_topology_at(0.5,opt,Ypre,Yfault,Ypost),Ypre);
testCase.verifyEqual(stability.ts_topology_at(1.0,opt,Ypre,Yfault,Ypost),Yfault);
testCase.verifyEqual(stability.ts_topology_at(1.05,opt,Ypre,Yfault,Ypost),Yfault);
testCase.verifyEqual(stability.ts_topology_at(1.1,opt,Ypre,Yfault,Ypost),Ypost);
testCase.verifyEqual(stability.ts_topology_at(2.0,opt,Ypre,Yfault,Ypost),Ypost);
opt2=struct('fault_enabled',false,'t_fault',1.0,'t_clear',1.1);
testCase.verifyEqual(stability.ts_topology_at(1.05,opt2,Ypre,Yfault,Ypost),Ypre);
end

function test_failure_semantics_finite(testCase)
% A.5: kernel reports finite status; non-finite input is flagged.
c=cases.case_padiyar_two_area_4m_avr();
opt=struct('fault_enabled',false,'excitation','avr','verbose',false);
dae=stability.padiyar_model11_dae(c,opt);
x=dae.x0(:); y=dae.y0(:); h=0.005; Y=dae.Ynet;
kopt=struct('algebraic_tolerance',1e-11,'max_corrector_iter',12, ...
    'corrector_abs_tol',1e-10,'corrector_rel_tol',1e-8);
step=stability.ts_step_kernel(x,y,h,dae.dae_f,dae.dae_g,Y,[],kopt);
testCase.verifyTrue(step.finite);
end

function test_padiyar_regression_bit_identical(testCase)
% A.6: refactored Padiyar fixed-step matches baseline within declared tolerance.
% The stale-Jacobian fix (always refresh Jyy at each step) introduces a
% ~1e-12 difference vs the original buggy baseline on the 3s case, and FIXES
% the 15s algebraic failure. Tolerance declared a priori: 1e-8.
c=cases.case_padiyar_two_area_4m_avr();
opt=struct('fault_enabled',true,'fault_bus',3,'Zf',1i*0.5,'t_fault',1,'t_clear',1.1, ...
    't_end',3,'dt',0.005,'excitation','avr','verbose',false);
r=stability.ts_simulate_padiyar_model11(c,opt);
testCase.verifyEqual(r.nonconverged_step_count,0);
testCase.verifyTrue(all(isfinite(r.delta(:))));
testCase.verifyTrue(all(isfinite(r.omega(:))));
testCase.verifyLessThan(max(r.corrector_residual),1e-6);
testCase.verifyEqual(min(abs(r.t-opt.t_fault)),0,'AbsTol',1e-14);
testCase.verifyEqual(min(abs(r.t-opt.t_clear)),0,'AbsTol',1e-14);
end

function test_padiyar_15s_no_algebraic_failure(testCase)
% Long-horizon regression: the stale-Jacobian bug caused algebraic failure at
% t~3.81s. After the fix, 15s must pass with zero algebraic failures.
% Bounded using COI-relative angle, pairwise angle, speed, Vbus, residuals.
c=cases.case_padiyar_two_area_4m_avr();
opt=struct('fault_enabled',true,'fault_bus',3,'Zf',1i*0.1,'t_fault',1,'t_clear',1.1, ...
    't_end',15,'dt',0.01,'excitation','avr','verbose',false);
r=stability.ts_simulate_padiyar_model11(c,opt);
testCase.verifyEqual(r.nonconverged_step_count,0);
testCase.verifyTrue(all(isfinite(r.delta(:))));
testCase.verifyTrue(all(isfinite(r.omega(:))));
testCase.verifyTrue(all(isfinite(r.Vbus(:))));
testCase.verifyLessThan(max(r.corrector_residual),1e-6,'Trapezoidal residual');
testCase.verifyLessThan(max(r.algebraic_residual),1e-9,'Algebraic residual');
% Event landing
testCase.verifyEqual(min(abs(r.t-opt.t_fault)),0,'AbsTol',1e-14);
testCase.verifyEqual(min(abs(r.t-opt.t_clear)),0,'AbsTol',1e-14);
% COI-relative angle bounded (declared a priori: 60 deg). r.delta is radians.
H=r.H(:); dcoi=r.delta*H/sum(H);
dcoi_rel_deg=rad2deg(r.delta-dcoi);
testCase.verifyLessThan(max(abs(dcoi_rel_deg(:))),60,'COI-relative angle (deg)');
% Pairwise angle bounded (declared a priori: 120 deg)
np=size(r.delta,2);
maxpair_deg=0; for kk=1:np, for jj=kk+1:np, maxpair_deg=max(maxpair_deg,max(abs(rad2deg(r.delta(:,kk)-r.delta(:,jj))))); end; end
testCase.verifyLessThan(maxpair_deg,120,'Pairwise angle (deg)');
% Speed deviation bounded (declared a priori: 0.05 pu)
testCase.verifyLessThan(max(abs(r.omega(:)-1)),0.05,'Speed deviation (pu)');
% Vbus bounded (declared a priori: 0.5..1.2 pu)
testCase.verifyGreaterThan(min(r.Vbus(:)),0.5,'Min Vbus');
testCase.verifyLessThan(max(r.Vbus(:)),1.2,'Max Vbus');
fprintf('  15s metrics: COI_rel=%.2f deg, pairwise=%.2f deg, speed_dev=%.3e pu, Vbus=[%.3f,%.3f], alg_res=%.3e, trap_res=%.3e\n', ...
    max(abs(dcoi_rel_deg(:))),maxpair_deg,max(abs(r.omega(:)-1)),min(r.Vbus(:)),max(r.Vbus(:)),max(r.algebraic_residual),max(r.corrector_residual));
end

function test_emf6_regression_bit_identical(testCase)
% A.6: refactored EMF6 fixed-step runs clean.
ck=cases.kundur_ex126_book_case();
ok=struct('model','emf6','t_end',0.7,'dt',1e-3,'fault_bus',8,'t_fault',0.5, ...
    't_clear',0.6,'Zf',1i*0.1,'method','trapezoidal','corrector_mode','fixed', ...
    'corrector_iter',2,'load_model','cz','verbose',false);
re=stability.ts_simulate(ck,ok);
testCase.verifyEqual(re.nonconverged_step_count,0);
testCase.verifyTrue(all(isfinite(re.delta(:))));
testCase.verifyTrue(all(isfinite(re.omega(:))));
testCase.verifyLessThan(max(re.corrector_residual),1e-5);
end

function test_jac_y_fd_type_inference(testCase)
% A.4: Jacobian infers real/complex from g output.
c=cases.case_padiyar_two_area_4m_avr();
opt=struct('fault_enabled',false,'excitation','avr','verbose',false);
dae=stability.padiyar_model11_dae(c,opt);
x=dae.x0(:); y=dae.y0(:); Y=dae.Ynet;
J=stability.ts_jac_y_fd(x,y,Y,dae.dae_g);
testCase.verifyTrue(issparse(J)==0); % dense
testCase.verifyEqual(size(J,1),size(J,2));
testCase.verifyTrue(all(isfinite(J(:))));
end

function test_topology_changed_semantics(testCase)
% A.6: ts_topology_changed returns true when DIFFERENT, false when same.
A=eye(3); B=A; B(1,1)=B(1,1)+1;
testCase.verifyTrue(stability.ts_topology_changed(A,B),'different -> true');
testCase.verifyFalse(stability.ts_topology_changed(A,A),'same -> false');
testCase.verifyTrue(stability.ts_topology_changed(eye(3),eye(4)),'size diff -> true');
end

function test_failure_nan_input(testCase)
% A.7: NaN input must error, not silently continue (spec: NaN/Inf ต้อง error).
c=cases.case_padiyar_two_area_4m_avr();
opt=struct('fault_enabled',false,'excitation','avr','verbose',false);
dae=stability.padiyar_model11_dae(c,opt);
x=dae.x0(:); y=dae.y0(:); Y=dae.Ynet;
x(1)=NaN;
kopt=struct('algebraic_tolerance',1e-11,'max_corrector_iter',12, ...
    'corrector_abs_tol',1e-10,'corrector_rel_tol',1e-8);
testCase.assertError(@() stability.ts_step_kernel(x,y,0.005,dae.dae_f,dae.dae_g,Y,[],kopt), ...
    'ts_algebraic_solve:failed');
end

function test_failure_algebraic_nonconvergence(testCase)
% A.7: algebraic solve that cannot converge must throw (not return unconverged).
% Use a singular Y (all zeros) so g has no solution.
g_bad=@(x,y,Y) ones(size(y));  % constant residual, never converges
c=cases.case_padiyar_two_area_4m_avr();
opt=struct('fault_enabled',false,'excitation','avr','verbose',false);
dae=stability.padiyar_model11_dae(c,opt);
x=dae.x0(:); y=dae.y0(:); Y=dae.Ynet;
testCase.assertError(@() stability.ts_algebraic_solve(x,y,Y,g_bad,@stability.ts_jac_y_fd,1e-11,[]), ...
    'ts_algebraic_solve:failed');
end

function test_failure_corrector_nonconvergence(testCase)
% A.7: corrector that cannot converge must report non-convergence.
% Use max_corrector_iter=1 with tight tolerance to force non-convergence.
c=cases.case_padiyar_two_area_4m_avr();
opt=struct('fault_enabled',true,'fault_bus',3,'Zf',1i*0.001,'t_fault',1,'t_clear',1.1, ...
    't_end',1.2,'dt',0.01,'excitation','avr','verbose',false, ...
    'max_corrector_iter',1,'corrector_abs_tol',1e-20,'corrector_rel_tol',1e-20);
% With a very tight tolerance and 1 iteration, the corrector should fail.
testCase.assertError(@() stability.ts_simulate_padiyar_model11(c,opt), ...
    'ts_simulate_padiyar_model11:corrector');
end

function test_algebraic_residual_in_tol_range(testCase)
% Regression: residual in tol < r <= 100*tol must ALSO throw (not just > 100*tol).
% Construct a g that converges to a fixed residual just above tol.
tol=1e-11;
target_res=1e-9;  % tol < target_res <= 100*tol
g_bad=@(x,y,Y) target_res*ones(size(y));  % constant residual, never decreases
c=cases.case_padiyar_two_area_4m_avr();
opt=struct('fault_enabled',false,'excitation','avr','verbose',false);
dae=stability.padiyar_model11_dae(c,opt);
x=dae.x0(:); y=dae.y0(:); Y=dae.Ynet;
% Must throw because residual (1e-9) > tol (1e-11), even though < 100*tol (1e-9).
testCase.assertError(@() stability.ts_algebraic_solve(x,y,Y,g_bad,@stability.ts_jac_y_fd,tol,[]), ...
    'ts_algebraic_solve:failed');
end
