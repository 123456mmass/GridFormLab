function op = smib_dq_init(machine, network, operating)
%SMIB_DQ_INIT Initial steady-state d-q operating point for SMIB detailed model.
%   OP = SMIB_DQ_INIT(MACHINE, NETWORK, OPERATING) computes the complete
%   steady-state d-q axis quantities for a single-machine infinite-bus
%   system with a detailed (two-axis flux) synchronous machine model,
%   following the procedure in Kundur Example 12.3 / Section 12.6.
%
%   Inputs:
%     MACHINE  - struct: Ladu, Laqu, Ll, Ra, Lfd, Rfd, and saturation
%                params Asat, Bsat, psi_T1
%     NETWORK  - struct: RE, XE (external resistance/reactance to inf. bus)
%     OPERATING- struct: P, Q, Et_mag (terminal P, Q, |Et|)
%
%   Output OP (struct) includes: Ksd, Ksd_incr, Lads, Laqs, Lads_incr,
%     delta_i, ed0, eq0, id0, iq0, It_mag, phi, delta0_rad/deg, EB,
%     ifd0, Efd0, psi_ad0, psi_aq0, psi_fd0, psi_at.
%
%   Reference: Kundur Sec 12.6 procedure (pages 759-761), Example 12.3.

Ladu = machine.Ladu;
Laqu = machine.Laqu;
Ll   = machine.Ll;
Ra   = machine.Ra;
Lfd  = machine.Lfd;

RE = network.RE;
XE = network.XE;

P  = operating.P;
Q  = operating.Q;
Et = operating.Et_mag;

% Terminal current magnitude and power-factor angle
S = hypot(P, Q);
It_mag = S / Et;
phi = atan2(Q, P);          % power factor angle (lagging positive)

% --- Saturation at the initial operating point -------------------------
% Air-gap flux linkage magnitude: psi_at = |Et + (Ra + jXl) It|
% with the terminal current taken at angle -phi relative to Et.
It_phasor = It_mag * exp(-1i * phi);     % Et taken as reference (angle 0)
Et_phasor = Et + 0i;
psi_at = abs(Et_phasor + (Ra + 1i * Ll) * It_phasor);

sat_params = struct('Asat', machine.Asat, 'Bsat', machine.Bsat, ...
    'psi_T1', machine.psi_T1);
sat = smib.smib_saturation(psi_at, sat_params);

Ksd = sat.Ksd_total;
Ksq = Ksd;                  % assume same saturation on both axes (Kundur Ex 12.3)
Lads = Ksd * Ladu;
Laqs = Ksq * Laqu;
Lads_incr = sat.Ksd_incr * Ladu;

% Saturated synchronous reactances
Xds = Lads + Ll;
Xqs = Laqs + Ll;

% --- Internal rotor angle delta_i (Kundur procedure step b) ------------
% delta_i = angle of (Et + (Ra + jXqs) It)
E_delta = Et_phasor + (Ra + 1i * Xqs) * It_phasor;
delta_i = angle(E_delta);

% Project terminal voltage and current onto rotor d-q axes
ed0 = Et * sin(delta_i);
eq0 = Et * cos(delta_i);
id0 = It_mag * sin(delta_i + phi);
iq0 = It_mag * cos(delta_i + phi);

% --- Resolve onto network (infinite bus) reference ---------------------
% Infinite-bus voltage components in machine d-q frame
EBd0 = ed0 - RE * id0 + XE * iq0;
EBq0 = eq0 - RE * iq0 - XE * id0;
EB = hypot(EBd0, EBq0);

% Rotor angle relative to infinite bus: angle between the q-axis and the
% infinite-bus voltage EB, measured from its d-q components (Kundur Ex 12.3).
delta0_rad = atan2(EBd0, EBq0);

% --- Field quantities --------------------------------------------------
% Field current and excitation voltage (steady state)
ifd0 = (eq0 + Ra * iq0 + Xds * id0) / Lads;
Efd0 = Ladu * ifd0;

% Air-gap flux linkages
psi_ad0 = Lads * (-id0 + ifd0);
psi_aq0 = -Laqs * iq0;
psi_fd0 = (Lads + Lfd) * ifd0 - Lads * id0;

op = struct();
op.It_mag = It_mag;
op.phi = phi;
op.psi_at = psi_at;
op.psi_I = sat.psi_I;
op.Ksd = Ksd;
op.Ksq = Ksq;
op.Ksd_incr = sat.Ksd_incr;
op.Lads = Lads;
op.Laqs = Laqs;
op.Lads_incr = Lads_incr;
op.Xds = Xds;
op.Xqs = Xqs;
op.delta_i = delta_i;
op.delta_i_deg = rad2deg(delta_i);
op.ed0 = ed0;
op.eq0 = eq0;
op.id0 = id0;
op.iq0 = iq0;
op.EBd0 = EBd0;
op.EBq0 = EBq0;
op.EB = EB;
op.delta0_rad = delta0_rad;
op.delta0_deg = rad2deg(delta0_rad);
op.ifd0 = ifd0;
op.Efd0 = Efd0;
op.psi_ad0 = psi_ad0;
op.psi_aq0 = psi_aq0;
op.psi_fd0 = psi_fd0;
end
