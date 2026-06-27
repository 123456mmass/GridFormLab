function r = kundur_6order_sauer_pai_equations()
%KUNDUR_6ORDER_SAUER_PAI_EQUATIONS 6th-order generator equations used for
%Kundur Example 12.6 small-signal stability analysis (SSSA).
%
% This file is intentionally short so it can be shared as the equation
% reference for the SSSA work. The executable implementation is in:
%   +stability/kundur_ex126_sixth_order_ssa.m
%   +stability/kundur_ex126_sauer_pai_ssa.m
%
% No MATLAB Power System Toolbox, Simscape powerlib, MATPOWER, PSAT, PSS/E,
% PowerWorld, DigSILENT, OpenDSS, Pandapower, or PyPower is used.
%
% -------------------------------------------------------------------------
% Generator model: 6th-order Sauer-Pai synchronous machine
% -------------------------------------------------------------------------
% State vector per generator i:
%   x_i = [ delta_i; omega_i; E'_qi; E'_di; psi''_di; psi''_qi ]
%
% Constant manual-excitation inputs at the operating point:
%   E_fd = constant
%   T_m  = constant
%
% Gamma factors:
%   gamma_d1 = (X''_d - X_l) / (X'_d - X_l)
%   gamma_q1 = (X''_q - X_l) / (X'_q - X_l)
%   gamma_d2 = (1 - gamma_d1) / (X'_d - X_l)
%   gamma_q2 = (1 - gamma_q1) / (X'_q - X_l)
%
% Gamma-coupled subtransient internal voltages:
%   E''_q = gamma_d1 E'_q + (1 - gamma_d1) psi''_d
%   E''_d = gamma_q1 E'_d + (1 - gamma_q1) psi''_q
%
% Stator algebraic equations (generator-current convention):
%   V_d = E''_d - R_a I_d + X''_q I_q
%   V_q = E''_q - R_a I_q - X''_d I_d
%
% Effective currents in the transient-flux equations:
%   I_d,eff = gamma_d1 I_d + gamma_d2 (E'_q - psi''_d)
%   I_q,eff = gamma_q1 I_q + gamma_q2 (psi''_q - E'_d)
%
% Differential equations:
%   d(delta)/dt = omega_0 omega
%   d(omega)/dt = (T_m - T_e - D omega) / (2H)
%   dE'_q/dt    = (E_fd - E'_q - (X_d - X'_d) I_d,eff) / T'_d0
%   dE'_d/dt    = (-E'_d + (X_q - X'_q) I_q,eff) / T'_q0
%   dpsi''_d/dt = (E'_q - psi''_d - (X'_d - X_l) I_d) / T''_d0
%   dpsi''_q/dt = (E'_d - psi''_q + (X'_q - X_l) I_q) / T''_q0
%
% Electromagnetic air-gap torque:
%   T_e = V_d I_d + V_q I_q + R_a (I_d^2 + I_q^2)
%
% Network algebraic equations:
%   I_network(V) - I_generator(delta, E', psi'', V) = 0
%
% Linearisation:
%   [ dx/dt ] = f(x,y)
%   [  0   ] = g(x,y)
%   A_red = f_x - f_y * (g_y \ g_x)
%   lambda = eig(A_red)
%
% -------------------------------------------------------------------------
% Run the implemented SSSA and print a compact eigenvalue list
% -------------------------------------------------------------------------
r = stability.kundur_ex126_sixth_order_ssa();
fprintf('6th-order Sauer-Pai SSSA: eigenvalues=%d, DAE residual=%.3e\n', ...
    numel(r.eigenvalues), r.newton_residual);
lam = r.eigenvalues;
[~, idx] = sort(real(lam), 'descend');
lam = lam(idx);
fprintf('  No.        Real           Imag          f(Hz)\n');
for k = 1:numel(lam)
    fprintf('%4d  %12.6f  %+12.6f  %9.4f\n', k, real(lam(k)), imag(lam(k)), abs(imag(lam(k)))/(2*pi));
end
end
