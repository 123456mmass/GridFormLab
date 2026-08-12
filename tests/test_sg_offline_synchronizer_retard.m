function tests = test_sg_offline_synchronizer_retard()
%TEST_SG_OFFLINE_SYNCHRONIZER_RETARD  The breaker-open synchronizer must be
%able to RETARD the rotor, not only accelerate it.
%
% Root cause of the production SG reclose SYNC_TIMEOUT (ADAPT/RECLOSE
% 2026-08-12): the offline synchronizer command was floored at Pmin=0. When the
% SG leads the grid angle, the proportional angle term K_theta*e_theta demands a
% NEGATIVE (decelerating) command; with Pmin=0 it clips to 0, and because the
% model damping D*omega vanishes at omega=0 (deviation) the rotor coasts to grid
% speed at a frozen angle offset -> the guard's dtheta never reaches the +-band
% -> timeout. Fix: symmetric authority Pmin=-Pmax for the breaker-open
% synchronizer actuator (a governor speed/torque bias, PROJECT_DERIVED), which
% restores the closed loop
%   d^2 e_theta/dt^2 + 2 zeta omega_n d e_theta/dt + omega_n^2 e_theta = 0.
%
% These tests drive the PRODUCTION helper stability.sg_offline_synchronizer_step
% (not a reimplementation). Oracle = the documented swing/kinematics equations.

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function opt = base_opt(Pmin)
% Gains from the production controller (H=2.5,D=1,omega_n=0.8,zeta=1) at 60 Hz.
opt = struct('H',2.5,'D',1.0,'omega_0',2*pi*60,'omega_n',0.8,'zeta',1.0, ...
    'Tsv',0.30,'Tch',0.20,'Pmin',Pmin,'Pmax',1.3462);
end

function test_negative_command_is_clipped_by_zero_floor(testCase)
% SG leads the grid (phase_error<0), speed matched (e_omega=0): the raw command
% is negative. With Pmin=0 it must clip to exactly 0 (the bug); with Pmin=-Pmax
% it must pass through negative (the fix).
phase_error = deg2rad(-106);   % SG angle ahead of grid
omega_sg = 0; omega_grid = 0;  % speeds matched
h = 0.01;

o0 = base_opt(0);
[~,~,cmd0,audit0] = stability.sg_offline_synchronizer_step(0,0,omega_sg,omega_grid,phase_error,h,o0);
testCase.verifyLessThan(audit0.command_raw, 0, ...
    'raw command must be negative when the SG leads the grid');
testCase.verifyEqual(cmd0, 0, 'AbsTol', 0, ...
    'Pmin=0 must clip the decelerating command to zero (the defect)');

oS = base_opt(-1.3462);
[~,~,cmdS,auditS] = stability.sg_offline_synchronizer_step(0,0,omega_sg,omega_grid,phase_error,h,oS);
testCase.verifyEqual(cmdS, auditS.command_raw, 'AbsTol', 1e-12, ...
    'Pmin=-Pmax must pass the negative command through (the fix)');
testCase.verifyLessThan(cmdS, 0);
end

function test_closed_loop_converges_only_with_symmetric_floor(testCase)
% Integrate the documented breaker-open loop
%   2H dw/dt = Pm - D w ,  de_theta/dt = -w0 w ,  w_grid=0,
% with Pm advanced by the PRODUCTION helper, from a +106 deg standing error.
% Pmin=-Pmax must drive e_theta into the +-10 deg band; Pmin=0 must not.
e0 = deg2rad(106); h = 1e-3; T = 40; n = round(T/h);
w0 = 2*pi*60; H = 2.5; D = 1.0;

    function [efinal, entered] = run(Pmin)
        o = base_opt(Pmin);
        e = e0; w = 0; Psv = 0; Pm = 0; entered = false;
        for k = 1:n
            [Psv,Pm,~] = stability.sg_offline_synchronizer_step(Psv,Pm,w,0,e,h,o);
            w = w + h*(Pm - D*w)/(2*H);
            e = e + h*(-w0*w);
            if abs(rad2deg(e)) <= 10, entered = true; end
        end
        efinal = rad2deg(e);
    end

[eS, enteredS] = run(-1.3462);
[e0f, entered0] = run(0);

testCase.verifyTrue(enteredS, 'Pmin=-Pmax must bring e_theta within +-10 deg');
testCase.verifyLessThan(abs(eS), 10, ...
    'Pmin=-Pmax must settle e_theta near zero');
% The zero floor fails to hold alignment: it cannot decelerate, so it never
% settles inside the band (it drifts/overshoots to a large residual).
testCase.verifyGreaterThan(abs(e0f), 10, ...
    'Pmin=0 must fail to settle e_theta (demonstrates the defect)');
testCase.verifyFalse(entered0 && abs(e0f) < 10, ...
    'Pmin=0 must not end synchronized');
end

function test_gains_place_second_order_poles(testCase)
% The derived gains must realize the requested critically-damped 2nd-order
% relative-angle loop: K_omega = 4 H zeta omega_n - D, K_theta = 2 H omega_n^2/omega_0.
o = base_opt(-1.3462);
[~,~,~,a] = stability.sg_offline_synchronizer_step(0,0,0,0,0.1,0.01,o);
testCase.verifyEqual(a.K_omega, 4*o.H*o.zeta*o.omega_n - o.D, 'RelTol',1e-12);
testCase.verifyEqual(a.K_theta, 2*o.H*o.omega_n^2/o.omega_0, 'RelTol',1e-12);
testCase.verifyGreaterThanOrEqual(a.K_omega, 0);
testCase.verifyGreaterThan(a.K_theta, 0);
end
