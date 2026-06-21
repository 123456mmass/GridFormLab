function K = smib_k_constants(machine, network, op, w0)
%SMIB_K_CONSTANTS K-constants for the SMIB field-circuit small-signal model.
%   K = SMIB_K_CONSTANTS(MACHINE, NETWORK, OP, W0) derives the linearized
%   K-constants K1, K2 (and K3, K4, T3) plus the field-equation state
%   matrix entries a32, a33, b3, from the machine d-q parameters and the
%   steady-state operating point OP (from SMIB_DQ_INIT).
%
%   State ordering for the 3-state model: [d_omega_r; d_delta; d_psi_fd].
%
%   Reference: Kundur Sec 12.3.2, eqs 12.105-12.120.

RE  = network.RE;
XE  = network.XE;
Ra  = machine.Ra;
Lfd = machine.Lfd;
Rfd = machine.Rfd;
Ll  = machine.Ll;
Ladu = machine.Ladu;

% Incremental (saturated) mutual inductances for perturbation analysis
Lads = op.Lads_incr;            % L'_ads incremental d-axis mutual (eq 12.117)
Laqs = op.Ksd_incr * machine.Laqu;   % incremental q-axis mutual

% L'ads: parallel of incremental Lads and field leakage Lfd (eq 12.91)
Lads_p = 1 / (1/Lads + 1/Lfd);

% Saturated incremental synchronous inductances along each axis
Lds_p = Lads_p + Ll;            % d-axis transient-like (with field)
Lqs   = Laqs + Ll;              % q-axis

% Network total impedance seen from internal node (eq 12.105)
RT  = Ra + RE;
XTq = XE + Lqs;
XTd = XE + Lds_p;
D   = RT^2 + XTq * XTd;

EB     = op.EB;
delta0 = op.delta0_rad;
sd = sin(delta0);
cd = cos(delta0);

% Current sensitivity coefficients (eq 12.108).
% Note: m2/n2 use the incremental mutual inductance Lads (no prime),
% while the reactances XTd etc. use L'ads (parallel of Lads and Lfd).
m1 = EB * (XTq * sd - RT * cd) / D;
n1 = EB * (RT * sd + XTd * cd) / D;
m2 = (XTq / D) * Lads / (Lads + Lfd);
n2 = (RT  / D) * Lads / (Lads + Lfd);

% Operating-point flux linkages and currents
psi_ad0 = op.psi_ad0;
psi_aq0 = op.psi_aq0;
id0 = op.id0;
iq0 = op.iq0;

% K1, K2 (eqs 12.113-12.114)
% Delta Te = K1*Delta delta + K2*Delta psi_fd
K1 = n1 * (psi_ad0 + Laqs * id0) - m1 * (psi_aq0 + Lads_p * iq0);
K2 = n2 * (psi_ad0 + Laqs * id0) - m2 * (psi_aq0 + Lads_p * iq0) ...
     + (Lads_p / Lfd) * iq0;

% Field-circuit effective time constant T3 = -1/a33 (eq 12.120)
Lads_unsat_p = 1 / (1/Ladu + 1/Lfd); %#ok<NASGU>

% State-matrix entries for the field flux equation (eq 12.116)
% d(Delta psi_fd)/dt = a32*Delta delta + a33*Delta psi_fd + b3*Delta E_fd
coef = w0 * Rfd / Lfd;
a32 = -coef * m1 * Lads_p;
a33 = -coef * (1 - Lads_p / Lfd + m2 * Lads_p);
b3  = w0 * Rfd / Ladu;          % input gain from Delta E_fd

% Effective T3 from a33 (eq 12.120): a33 = -1/T3
T3 = -1 / a33;

% K4 (eq 12.115): a32 = -(w0*Rfd/Ladu)*K4, hence
K4 = (Ladu / Rfd) * (-a32) / w0;

K = struct();
K.m1 = m1; K.n1 = n1; K.m2 = m2; K.n2 = n2;
K.K1 = K1; K.K2 = K2; K.K4 = K4; K.T3 = T3;
K.a32 = a32; K.a33 = a33; K.b3 = b3;
K.RT = RT; K.XTq = XTq; K.XTd = XTd; K.D = D;
K.Lads_p = Lads_p; K.Lads_incr = Lads; K.Laqs_incr = Laqs;
end
