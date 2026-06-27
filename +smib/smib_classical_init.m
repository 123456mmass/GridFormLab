function op = smib_classical_init(machine, network, operating)
%SMIB_CLASSICAL_INIT Initial operating point for the SMIB classical model.
%   OP = SMIB_CLASSICAL_INIT(MACHINE, NETWORK, OPERATING) computes the
%   steady-state internal voltage E' behind the transient reactance X'd,
%   the rotor angle delta0 (relative to the infinite bus), the total
%   reactance XT, and the synchronizing torque coefficient Ks for the
%   classical machine model.
%
%   Inputs (structs):
%     MACHINE.Xd_t   - transient reactance X'd (pu)
%     NETWORK.X_E    - external reactance E'-node -> infinite bus (pu)
%     OPERATING      - terminal conditions: P, Q, Et_mag, Et_ang_deg,
%                      EB_mag, EB_ang_deg
%
%   Output OP fields:
%     It            - terminal current phasor (complex, pu)
%     Ep            - internal voltage E' phasor (complex, pu)
%     Ep_mag        - |E'| (pu)
%     delta0_rad    - rotor angle wrt infinite bus (rad)
%     delta0_deg    - rotor angle (deg)
%     XT            - X'd + X_E (pu)
%     Ks            - synchronizing torque coefficient (Kundur eq 12.76)
%
%   Reference: Kundur Sec 12.3.1, eqs 12.71-12.76.

Xd_t = machine.Xd_t;
X_E  = network.X_E;

P  = operating.P;
Q  = operating.Q;
Et = operating.Et_mag * exp(1i * deg2rad(operating.Et_ang_deg));
EB = operating.EB_mag * exp(1i * deg2rad(operating.EB_ang_deg));

% Terminal current from complex power S = Et * conj(It) = P + jQ
It = conj((P + 1i * Q) / Et);

% Internal voltage behind transient reactance (Ra neglected in classical model)
Ep = Et + 1i * Xd_t * It;
Ep_mag = abs(Ep);

% Rotor angle of E' relative to the infinite bus
delta0_rad = angle(Ep) - angle(EB);

% Total reactance between internal voltage and infinite bus
XT = Xd_t + X_E;

% Synchronizing torque coefficient (Kundur eq 12.76)
Ks = (Ep_mag * abs(EB) / XT) * cos(delta0_rad);

op = struct();
op.It = It;
op.Ep = Ep;
op.Ep_mag = Ep_mag;
op.delta0_rad = delta0_rad;
op.delta0_deg = rad2deg(delta0_rad);
op.XT = XT;
op.Ks = Ks;
op.EB_mag = abs(EB);
op.Et_mag = abs(Et);
end
