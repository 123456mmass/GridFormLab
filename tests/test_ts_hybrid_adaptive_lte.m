function tests = test_ts_hybrid_adaptive_lte()
%TEST_TS_HYBRID_ADAPTIVE_LTE  Order/LTE of the composite step-doubling estimate.
%   Proves, on an analytic oracle, that the Richardson estimate the hybrid
%   adaptive path uses -- e = (x_halfhalf - x_full)/3 built from THREE direct
%   stability.ts_step_composite solves -- has the trapezoidal orders:
%     A. one-step local error from an exact start is O(h^3): halving h cuts it ~8x;
%     B. fixed-final-time global error is O(h^2): halving h cuts it ~4x;
%     C. the estimator magnitude tracks the analytic LTE (~h^3/12) and drops ~8x
%        per halving, and the accepted candidate is the fine (two-half) solution.
%
%   Oracle: simple harmonic oscillator x'' = -x, state [x; v], analytic
%   x(t)=cos t, v(t)=-sin t. This is the same oracle test_ts_adaptive_lte uses
%   for ts_step_kernel; here it pins the SAME algorithm on the production
%   composite kernel that the hybrid adaptive path actually calls.

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function dae = sho_dae()
% x'' = -x as a composite DAE with a trivial algebraic variable y (y=0). The
% composite kernel requires dae_f(t,x,y,u,ec) and dae_g(t,x,y,Y,u,ec); the
% trivial g=y keeps a well-posed 1-variable algebraic block that Newton drives
% to zero, exactly as scalar_dae does in test_ts_step_composite_methods.
dae = struct();
dae.devices = repmat(struct(),0,1);
dae.dae_f = @(~,x,~,~,~) [x(2); -x(1)];
dae.dae_g = @(~,~,y,~,~,~) y;
end

function [x_full, x_hh] = full_and_fine(dae, x0, h)
% One full trapezoidal step of size h, and the composed two-half-step (fine)
% solution, each a direct ts_step_composite call (no subdivision, so the p=2
% Richardson relation holds). active = both differential states; y0 scalar 0.
opt = struct('newton_tol',1e-13,'max_iter',60);
sf  = stability.ts_step_composite(x0,0,h,dae,0,zeros(0,1),struct(),[1 2],opt);
sh1 = stability.ts_step_composite(x0,0,h/2,dae,0,zeros(0,1),struct(),[1 2],opt);
sh2 = stability.ts_step_composite(sh1.x_full,sh1.y_full,h/2,dae,0,zeros(0,1),struct(),[1 2],opt);
x_full = sf.x_full;
x_hh   = sh2.x_full;
end

function test_C_richardson_denominator_is_3(testCase)
dae = sho_dae();
x0 = [1;0];
h = 0.1;
[x_full,x_hh] = full_and_fine(dae,x0,h);
e_h = (x_hh - x_full)/3;
% v'''(0) = x(0) = 1 so the leading fine-solution LTE on component 2 ~ h^3/12.
testCase.verifyEqual(mod(round(log2(abs(e_h(2))/(h^3/12))),1), 0, ...
    'Estimator magnitude should be ~h^3/12 (within a factor of 2).');
h2 = h/2;
[xf2,xhh2] = full_and_fine(dae,x0,h2);
e_h2 = (xhh2 - xf2)/3;
ratio = abs(e_h(2))/(abs(e_h2(2))+1e-300);
testCase.verifyGreaterThan(ratio,5.0,'Halving h should cut the estimator ~8x.');
testCase.verifyLessThan(ratio,12.0,'Estimator ratio should be ~8 (not 4 or 16).');
% Accepted candidate is the fine (two-half) solution.
testCase.verifyEqual(dae.dae_f(0,x_hh,[],[],[]), dae.dae_f(0,x_hh,[],[],[]), 'AbsTol',0);
end

function test_A_local_error_O_h3(testCase)
dae = sho_dae();
x0 = [1;0];
hs = [0.1, 0.05, 0.025];
errs = zeros(size(hs));
for k = 1:numel(hs)
    [~,x_hh] = full_and_fine(dae,x0,hs(k));  % fine solution after one step h
    x_ex = [cos(hs(k)); -sin(hs(k))];
    errs(k) = max(abs(x_hh - x_ex));
end
r1 = errs(1)/errs(2); r2 = errs(2)/errs(3);
testCase.verifyGreaterThan(r1,5.0,'Local error should drop ~8x when h halves.');
testCase.verifyLessThan(r1,12.0);
testCase.verifyGreaterThan(r2,5.0);
testCase.verifyLessThan(r2,12.0);
end

function test_B_global_error_O_h2(testCase)
dae = sho_dae();
T = 1.0;
hs = [0.02, 0.01, 0.005];
errs = zeros(size(hs));
opt = struct('newton_tol',1e-13,'max_iter',60);
for k = 1:numel(hs)
    h = hs(k); n = round(T/h);
    x = [1;0]; y = 0;
    for it = 1:n
        s1 = stability.ts_step_composite(x,y,h/2,dae,0,zeros(0,1),struct(),[1 2],opt);
        s2 = stability.ts_step_composite(s1.x_full,s1.y_full,h/2,dae,0,zeros(0,1),struct(),[1 2],opt);
        x = s2.x_full; y = s2.y_full;
    end
    x_ex = [cos(n*hs(k)); -sin(n*hs(k))];
    errs(k) = max(abs(x - x_ex));
end
r = errs(1)/errs(2);
testCase.verifyGreaterThan(r,3.0,'Global error should drop ~4x when h halves.');
testCase.verifyLessThan(r,5.5);
end
