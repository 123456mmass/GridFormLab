function r = kundur_6order_equations()
%KUNDUR_6ORDER_EQUATIONS 6th-order generator equations used for
%Kundur Example 12.6 small-signal stability analysis (SSSA).
%
% This file is intentionally short so it can be shared as the equation
% reference for the SSSA work. The executable implementation is in:
%   +stability/kundur_ex126_sixth_order_ssa.m
%   +stability/kundur_ex126_kundur_ssa.m
%
% No MATLAB Power System Toolbox, Simscape powerlib, MATPOWER, PSAT, PSS/E,
% PowerWorld, DigSILENT, OpenDSS, Pandapower, or PyPower is used.
%
% -------------------------------------------------------------------------
% Generator model: 6th-order Kundur/GENTPJ synchronous machine
% -------------------------------------------------------------------------
% State vector per generator i (subtransient EMFs as states):
%   x_i = [ delta_i; omega_i; E'_qi; E'_di; E''_qi; E''_di ]
%
% Constant manual-excitation inputs at the operating point:
%   E_fd = constant
%   T_m  = constant
%
% Stator algebraic equations (generator-current convention):
%   V_d = E''_d - R_a I_d + X''_q I_q
%   V_q = E''_q - R_a I_q - X''_d I_d
%
% Kundur/GENTPJ coefficients (saturation disabled, S_d = S_q = 0):
%   c_d = (X_d - X'_d) / (X'_d - X''_d)
%   d_d = (X_d - X''_d) / (X'_d - X''_d)
%   c_q = (X_q - X'_q) / (X'_q - X''_q)
%   d_q = (X_q - X''_q) / (X'_q - X''_q)
%
% Differential equations:
%   d(delta)/dt = omega_0 omega
%   d(omega)/dt = (T_m - T_e - D omega) / (2H)
%   dE'_q/dt    = (E_fd + c_d E''_q - d_d E'_q) / T'_d0
%   dE'_d/dt    = (c_q E''_d - d_q E'_d) / T'_q0
%   dE''_q/dt   = (E'_q - E''_q - (X'_d - X''_d) I_d) / T''_d0
%   dE''_d/dt   = (E'_d - E''_d + (X'_q - X''_q) I_q) / T''_q0
%
% Electromagnetic air-gap torque:
%   T_e = V_d I_d + V_q I_q + R_a (I_d^2 + I_q^2)
%
% Network algebraic equations:
%   I_network(V) - I_generator(delta, E', E'', V) = 0
%
% Linearisation:
%   [ dx/dt ] = f(x,y)
%   [  0   ] = g(x,y)
%   A_red = f_x - f_y * (g_y \ g_x)
%   lambda = eig(A_red)
%
% Reference: Kundur, Power System Stability and Control; MATLAB GENTPJ.
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
