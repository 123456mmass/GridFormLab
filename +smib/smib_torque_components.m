function td = smib_torque_components(K, exciter, H, w0, omega)
%SMIB_TORQUE_COMPONENTS Synchronizing/damping torque from field & AVR.
%   TD = SMIB_TORQUE_COMPONENTS(K, EXCITER, H, W0, OMEGA) decomposes the
%   air-gap torque contributed by the field-flux variation (with exciter
%   action) into synchronizing (in phase with delta_delta) and damping
%   (in phase with delta_omega_r) components, evaluated at rotor
%   oscillation frequency OMEGA (rad/s).
%
%   The field-flux response to a rotor-angle perturbation is
%     delta_psi_fd / delta_delta = -K3*[K4(1+sTR) + K5*KA]
%                                  / [(1+sT3)(1+sTR) + K3*K6*KA]
%   (Kundur eq 12.144 with G_ex = KA). The contribution to electrical
%   torque is delta_Te(psi_fd) = K2 * delta_psi_fd. Evaluated at s = j*omega,
%   the real part gives the synchronizing component K_S(delta_psi_fd) and
%   the imaginary part (scaled by omega/w0) the damping component
%   K_D(delta_psi_fd).
%
%   Reference: Kundur Sec 12.4, eqs 12.142-12.147, Table 12.1.

K3 = K.K3; K4 = K.K4; K5 = K.K5; K6 = K.K6; T3 = K.T3;
K2 = K.K2;
KA = exciter.KA;
TR = exciter.TR;

s = 1i * omega;

num = -K3 * (K4 * (1 + s * TR) + K5 * KA);
den = (1 + s * T3) * (1 + s * TR) + K3 * K6 * KA;
psifd_over_delta = num / den;

dTe_over_delta = K2 * psifd_over_delta;

% Synchronizing component: in phase with delta_delta (real part)
Ks_dpsifd = real(dTe_over_delta);

% Damping component: in phase with delta_omega_r = (s/w0)*delta_delta,
% so delta_Te = ... + KD * delta_omega_r => KD = imag(dTe/ddelta)*w0/omega
KD_dpsifd = imag(dTe_over_delta) * w0 / omega;

td = struct();
td.omega = omega;
td.psifd_over_delta = psifd_over_delta;
td.Ks_dpsifd = Ks_dpsifd;
td.KD_dpsifd = KD_dpsifd;
td.Ks_total = K.K1 + Ks_dpsifd;
td.H = H;
td.w0 = w0;
end
