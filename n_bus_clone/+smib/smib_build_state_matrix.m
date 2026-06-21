function sys = smib_build_state_matrix(model, params)
%SMIB_BUILD_STATE_MATRIX Assemble the SMIB small-signal state matrix.
%   SYS = SMIB_BUILD_STATE_MATRIX(MODEL, PARAMS) returns a struct SYS with
%   the state matrix A, input vector b, and state-variable names for the
%   requested MODEL of the single-machine infinite-bus system.
%
%   MODEL (char):
%     'A' - classical, 2 states  [d_omega_r; d_delta]          (Kundur 12.78)
%     'B' - + field circuit, 3 states [..; d_psi_fd]            (Kundur 12.116)
%     'C' - + exciter/AVR, 4 states   [..; d_v1]                (Kundur 12.140)
%     'D' - + PSS, 6 states           [..; d_v2; d_vs]          (Kundur 12.151)
%
%   PARAMS fields depend on the model (see each local builder below).
%
%   Reference: Kundur Sec 12.3-12.5.

model = upper(model);
switch model
    case 'A'
        sys = build_classical(params);
    case 'B'
        sys = build_field(params);
    case 'C'
        sys = build_avr(params);
    case 'D'
        sys = build_pss(params);
    otherwise
        error('smib_build_state_matrix:badModel', ...
            'Unknown model "%s". Use A, B, C, or D.', model);
end
sys.model = model;
end

% ------------------------------------------------------------------------
function sys = build_classical(p)
% Classical model, Kundur eq 12.78.
% States: x = [delta_omega_r (pu); delta_delta (rad)]
% d/dt x = A x + b * delta_Tm
H  = p.H;
KD = p.KD;
Ks = p.Ks;
w0 = p.w0;          % 2*pi*f0 (rad/s)

A = [ -KD/(2*H),  -Ks/(2*H);
       w0,          0       ];
b = [ 1/(2*H); 0 ];

sys = struct();
sys.A = A;
sys.b = b;
sys.state_names = {'\Delta\omega_r', '\Delta\delta'};
sys.Ks = Ks;
sys.KD = KD;
sys.H = H;
sys.w0 = w0;
end

% ------------------------------------------------------------------------
function sys = build_field(p)
% Field-circuit model, Kundur eq 12.116.
% States: x = [delta_omega_r (pu); delta_delta (rad); delta_psi_fd (pu)]
% d/dt x = A x + b * [delta_Tm; delta_Efd]
H  = p.H;
KD = p.KD;
w0 = p.w0;
K1 = p.K1;
K2 = p.K2;
a32 = p.a32;
a33 = p.a33;
b3  = p.b3;

A = [ -KD/(2*H),  -K1/(2*H),  -K2/(2*H);
       w0,          0,          0;
       0,           a32,        a33      ];

% Input columns: [delta_Tm, delta_Efd]
b = [ 1/(2*H), 0;
      0,       0;
      0,       b3 ];

sys = struct();
sys.A = A;
sys.b = b;
sys.state_names = {'\Delta\omega_r', '\Delta\delta', '\Delta\psi_{fd}'};
sys.K1 = K1; sys.K2 = K2;
sys.H = H; sys.KD = KD; sys.w0 = w0;
end

% ------------------------------------------------------------------------
function sys = build_avr(p)
% AVR / exciter model, Kundur eq 12.140-12.141.
% States: x = [d_omega_r; d_delta; d_psi_fd; d_v1]
%   d_v1 = terminal-voltage transducer output (exciter input)
% Exciter: G_ex(s) = KA, transducer time constant TR.
H  = p.H;  KD = p.KD;  w0 = p.w0;
K1 = p.K1; K2 = p.K2;  K3 = p.K3; K4 = p.K4; K5 = p.K5; K6 = p.K6;
T3 = p.T3; TR = p.TR;  KA = p.KA;

a32 = -K3 * K4 / T3;        % field eq, delta coupling
a33 = -1 / T3;              % field self time constant
a34 = -(K3 / T3) * KA;      % exciter -> field (Delta Efd = -KA*Delta v1)

A = [ -KD/(2*H),  -K1/(2*H),  -K2/(2*H),   0;
       w0,          0,          0,          0;
       0,           a32,        a33,        a34;
       0,           K5/TR,      K6/TR,     -1/TR ];

b = [ 1/(2*H); 0; 0; 0 ];   % Delta Tm input

sys = struct();
sys.A = A;
sys.b = b;
sys.state_names = {'\Delta\omega_r', '\Delta\delta', '\Delta\psi_{fd}', '\Delta v_1'};
sys.K = struct('K1',K1,'K2',K2,'K3',K3,'K4',K4,'K5',K5,'K6',K6, ...
    'T3',T3,'TR',TR,'KA',KA);
sys.H = H; sys.KD = KD; sys.w0 = w0;
end

% ------------------------------------------------------------------------
function sys = build_pss(p)
% AVR + PSS model, Kundur eq 12.151.
% States: x = [d_omega_r; d_delta; d_psi_fd; d_v1; d_v2; d_vs]
%   d_v2 = washout state, d_vs = lead-lag (PSS) output
% PSS: G_pss(s) = KSTAB * sTw/(1+sTw) * (1+sT1)/(1+sT2), input = d_omega_r.
H  = p.H;  KD = p.KD;  w0 = p.w0;
K1 = p.K1; K2 = p.K2;  K3 = p.K3; K4 = p.K4; K5 = p.K5; K6 = p.K6;
T3 = p.T3; TR = p.TR;  KA = p.KA;
KSTAB = p.KSTAB; Tw = p.Tw; T1 = p.T1; T2 = p.T2;

a32 = -K3 * K4 / T3;
a33 = -1 / T3;
gain_ef = (K3 / T3) * KA;     % exciter gain into field

% Rows 1-3 of the swing/field block (d_v1 enters field as -gain_ef,
% PSS output d_vs enters field as +gain_ef via the exciter summing point)
a11 = -KD/(2*H);  a12 = -K1/(2*H);  a13 = -K2/(2*H);

A = zeros(6);
% pd_omega_r
A(1,:) = [a11, a12, a13, 0, 0, 0];
% pd_delta
A(2,:) = [w0, 0, 0, 0, 0, 0];
% pd_psi_fd
A(3,:) = [0, a32, a33, -gain_ef, 0, gain_ef];
% pd_v1 (transducer of Et)
A(4,:) = [0, K5/TR, K6/TR, -1/TR, 0, 0];
% pd_v2 (washout): pd_v2 = KSTAB*pd_omega_r - (1/Tw)*d_v2
A(5,:) = [KSTAB*a11, KSTAB*a12, KSTAB*a13, 0, -1/Tw, 0];
% pd_vs (lead-lag): pd_vs = (T1/T2)*pd_v2 + (1/T2)*d_v2 - (1/T2)*d_vs
r = T1 / T2;
A(6,:) = [r*KSTAB*a11, r*KSTAB*a12, r*KSTAB*a13, 0, (1/T2 - r/Tw), -1/T2];

b = [ 1/(2*H); 0; 0; 0; 0; 0 ];

sys = struct();
sys.A = A;
sys.b = b;
sys.state_names = {'\Delta\omega_r', '\Delta\delta', '\Delta\psi_{fd}', ...
    '\Delta v_1', '\Delta v_2', '\Delta v_s'};
sys.K = struct('K1',K1,'K2',K2,'K3',K3,'K4',K4,'K5',K5,'K6',K6, ...
    'T3',T3,'TR',TR,'KA',KA,'KSTAB',KSTAB,'Tw',Tw,'T1',T1,'T2',T2);
sys.H = H; sys.KD = KD; sys.w0 = w0;
end
