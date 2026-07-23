function sys = build_ieee14_switch_system(opts)
%BUILD_IEEE14_SWITCH_SYSTEM  IEEE 14-bus network with 1 SG (bus 1) and 4
%   switchable GFL/GFM IBRs (buses 2,3,6,8) for the AGSI/AGSI++ mode-switch
%   study, using the SAME models as the Padiyar 4-machine study
%   (Padiyar model-1.1 SG via ibr.padiyar_sg_unit + ibr.SwitchableIbr6 reduced-6
%   IBRs). Returns the same sys contract as ibr.build_padiyar_switch_system, so
%   it plugs into ibr.padiyar_switch_tds / padiyar_switch_demo /
%   padiyar_switch_pf_sssa unchanged.
%
%   Network Y-bus is taken from the in-house Newton power flow
%   (pfsolver.powerflow_newton_raphson -> pf.Ybus), which is transformer-tap
%   aware; the constant-impedance loads are folded onto its diagonal. (The
%   Padiyar builder's stability.padiyar_model11_dae network model omits taps,
%   so it cannot be reused for the tapped IEEE14 network.)
%
%   Provenance (professional, cited):
%     - Network/base : IEEE 14-bus = MATPOWER 6.0 case14 (IEEE CDF), 100 MVA,
%       60 Hz (cases.case_ieee14bus; matches ITI/models reference/ieee-14bus).
%     - SG1 dynamics : Kodsi, U.Waterloo TR 2003-3 Table A.2, Gen1 bus 1,
%       615 MVA machine base, base-converted to 100 MVA here. ADAPTED to
%       Padiyar model-1.1: Kodsi has Tpq0=0, Xqp=Xq (no q-axis transient) =>
%       model-1.0; kept in the model-1.1 layout with Xqp=Xq (Edp0=0) and a
%       small Tpq0=0.033 s (Kodsi Tppq0) to keep the Edp ODE well-posed.
%     - Excitation : "manual" (constant field, NO AVR) and NO PSS per the
%       study constraint.
%   Classification: ASSUMED_DIAGNOSTIC study builder; project code only.

arguments
    opts.index_mode (1,1) string = "agsi_pp"
    opts.AGSI_up (1,1) double = 0.65
    opts.AGSI_down (1,1) double = 0.35
    opts.T_d_on (1,1) double = 0.0
    opts.T_d_off (1,1) double = 0.0
    opts.sg_bus (1,1) double = 1
    opts.ibr_buses (1,:) double = [2 3 6 8]
    opts.sg_droop_R (1,1) double = 0.05
    opts.gfm_ilim (1,1) double = 1.2
    opts.excitation (1,1) string = "manual"
end
pf_init_paths();

c = cases.case_ieee14bus();
pf = pfsolver.powerflow_newton_raphson(c, struct('verbose',false,'plot_results',false, ...
    'tolerance',1e-10,'max_iter',100,'enforce_q_limits',false));
if ~pf.converged
    error('ibr:build_ieee14_switch_system:powerFlow','In-house Newton PF did not converge.');
end
bus_ids = pf.external_bus_ids(:).';
nb = numel(bus_ids);

% --- dynamic admittance: tap-aware network Ybus + constant-Z loads --------
V0v = pf.bus_voltage(:).*exp(1i*deg2rad(pf.bus_angle_deg(:)));
load_adm = (pf.P_load(:) - 1i*pf.Q_load(:))./(abs(V0v).^2);
Y = pf.Ybus + diag(load_adm);
y0 = zeros(2*nb,1); y0(1:2:end) = real(V0v); y0(2:2:end) = imag(V0v);

% --- SG unit at the SG bus (Padiyar-1.1, Kodsi data, manual) --------------
dae = build_sg_dae(c, pf, opts.sg_bus, char(opts.excitation));
sg = ibr.padiyar_sg_unit(dae, 1, opts.sg_droop_R);

% --- network Thevenin impedance per bus (diagnostic SCR) ------------------
Z = inv(Y);   %#ok<MINV>

% --- four switchable IBRs at the remaining generator buses ----------------
nib = numel(opts.ibr_buses);
devs = cell(1,nib); x_ibr0 = cell(1,nib); ibr_bp = zeros(1,nib);
scr_bus = zeros(1,nib); Mbase = zeros(1,nib);
for j = 1:nib
    b = opts.ibr_buses(j); bp = find(bus_ids==b,1);
    if isempty(bp), error('ibr:build_ieee14_switch_system:ibrBus','IBR bus %d not found.',b); end
    V0 = complex(y0(2*bp-1), y0(2*bp));
    P = pf.P_generation(bp); Q = pf.Q_generation(bp);
    Mb = 100*max(abs(P + 1i*Q), 0.20);                 % machine rating (MVA); floor for P=0 units
    params = struct('Sbase',100,'Mbase',Mb,'fbase',c.base_values.frequency_Hz);
    d = ibr.SwitchableIbr6(sprintf("IBR%d",b), b, bp, bus_ids, V0, params, P, Q, ...
        index_mode=opts.index_mode, AGSI_up=opts.AGSI_up, AGSI_down=opts.AGSI_down, ...
        T_d_on=opts.T_d_on, T_d_off=opts.T_d_off);
    devs{j} = d; ibr_bp(j) = bp; Mbase(j) = Mb;
    d.ilim = opts.gfm_ilim * (Mb/100);                 % |I| <= i_max x rated (system base)
    x_ibr0{j} = d.gfl_dev.equilibrium_initialize(V0, P, Q, struct());
    scr_bus(j) = abs(V0)^2 / (abs(Z(bp,bp)) * max(abs(P+1i*Q),0.20));
end

sys = struct();
sys.classification = 'ASSUMED_DIAGNOSTIC_IEEE14_1SG_4IBR_SWITCH';
sys.sg = sg;
sys.devs = {devs{:}};
sys.Y = Y;
sys.bus_ids = bus_ids;
sys.pf = pf;
sys.y0 = y0;
sys.x_sg0 = sg.x0;
sys.x_ibr0 = {x_ibr0{:}};
sys.sg_bus = opts.sg_bus;
sys.sg_bus_position = sg.bus_position;
sys.ibr_buses = opts.ibr_buses;
sys.ibr_bus_positions = ibr_bp;
sys.scr_bus = scr_bus;
sys.scr_strong = 20;
sys.load_adm = load_adm;
sys.load_buses = bus_ids(abs(pf.P_load(:)).' + abs(pf.Q_load(:)).' > 0);
sys.Mbase = Mbase;
sys.nb = nb;
sys.base = c.base_values;
end

% =========================================================================
function dae = build_sg_dae(c, pf, sg_bus, exc)
% Minimal DAE-struct for ONE Padiyar model-1.1 machine at sg_bus, initialised
% from the power-flow operating point, in the ABI ibr.padiyar_sg_unit expects.
sZ = 100/615; sH = 615/100;                     % 615 MVA machine base -> 100 MVA
Ra=0.0; Xd=0.8979*sZ; Xdp=0.2995*sZ; Xq=0.646*sZ; Xqp=Xq;
Tpd0=7.4; Tpq0=0.033; KA=200; TA=0.02;
H=5.148*sH; D=2.0*sH; fb=c.base_values.frequency_Hz;

bp = find(pf.external_bus_ids==sg_bus,1);
V  = pf.bus_voltage(bp)*exp(1i*deg2rad(pf.bus_angle_deg(bp)));
S  = pf.P_generation(bp) + 1i*pf.Q_generation(bp);
I  = conj(S/V);
delta = angle(V + (Ra + 1i*Xq)*I);              % Ra=0 => exact 2-axis angle
[Id,Iq] = to_dq(I,delta); [Vd,Vq] = to_dq(V,delta);
Edp = (Xq-Xqp)*Iq;                              % = 0 (Xqp=Xq)
Eqp = Vq + Ra*Iq + Xdp*Id;
Efd = Eqp + (Xd-Xdp)*Id;
Te  = Vd*Id + Vq*Iq + Ra*(Id^2+Iq^2);

ns = 4 + strcmp(exc,'avr');
x0 = [delta;1;Eqp;Edp]; names = {'delta_SG1';'omega_SG1';'Eqp_SG1';'Edp_SG1'};
if strcmp(exc,'avr'), x0=[x0;Efd]; names=[names;{'Efd_SG1'}]; end

m = struct('Ra',Ra,'Xd',Xd,'Xdp',Xdp,'Xq',Xq,'Xqp',Xqp,'Tpd0',Tpd0,'Tpq0',Tpq0, ...
    'KA',KA,'TA',TA,'ng',1,'wB',2*pi*fb);
u = struct('H',H,'D',D,'bus_idx',bp,'bus_ids',sg_bus,'id',{{'SG1'}});
init = struct('Efd0',Efd,'Pm',Te,'Vref',abs(V)+Efd/KA,'bus_idx',bp,'states_per_machine',ns);
dae = struct('machine',m,'units',u,'init',init,'ns',ns,'x0',x0, ...
    'state_names',{names},'pf',pf,'excitation',exc,'gen_buses',sg_bus,'base',c.base_values);
end

function [d,q] = to_dq(z,delta)
d = sin(delta)*real(z) - cos(delta)*imag(z);
q = cos(delta)*real(z) + sin(delta)*imag(z);
end
