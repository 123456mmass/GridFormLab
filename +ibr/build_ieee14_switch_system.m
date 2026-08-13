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
    opts.ilim_mode (1,1) string = "clamp"   % converter current limiter: "clamp" (hard, default) | "vi" (soft virtual-impedance)
    opts.sg_H_scale (1,1) double = 1.0      % scale SG inertia/damping (grid-strength / effective-penetration sweep knob)
    opts.sg_X_scale (1,1) double = 1.0      % scale SG internal reactances Xd,Xdp,Xq,Xqp (effective electrical-distance / coupling-strength knob; 1.0 = unchanged, re-equilibrated consistently)
    opts.sg_H (1,1) double = NaN            % direct SOURCE_DEFINED override [s]
    opts.sg_D (1,1) double = NaN            % direct SOURCE_DEFINED override [pu]
    opts.excitation (1,1) string = "manual"
    opts.case_profile (1,1) string = "ieee14_baseline"
end
pf_init_paths();

switch lower(opts.case_profile)
    case "ieee14_baseline"
        c = cases.case_ieee14bus();
    case "eecon49_figure4"
        c = cases.case_ieee14bus_eecon49_switch();
    otherwise
        error('ibr:build_ieee14_switch_system:caseProfile', ...
            'Unknown case_profile "%s".',opts.case_profile);
end
% Phase F: Q-limit enforcement is now backed by real per-bus Qmin/Qmax
% (registered from mpc.gen in cases.case_matpower6_case14).  On the
% eecon49 operating point all inverter buses are PQ resources and the SG is
% the slack, so no PV bus triggers enforcement (rounds = 0); enabling the
% PF default is safe and correct for cases that do carry PV buses.
pf = pfsolver.powerflow_newton_raphson(c, struct('verbose',false,'plot_results',false, ...
    'tolerance',1e-10,'max_iter',100,'enforce_q_limits',true));
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

% --- SG unit at the SG bus --------------------------------------------------
% EECON49 uses the operational Kundur/GENTPJ sixth-order SG state.  The
% standalone EMF6 SSSA network model does not include IEEE14 transformer taps,
% so this profile supplies the same audited EMF6 coefficients with the
% tap-aware PF operating point; all SG equations remain in
% stability.sg_composite_device.
if lower(opts.case_profile) == "eecon49_figure4"
    emfp = build_emf6_override(c, pf, opts.sg_bus, opts.sg_H, opts.sg_D);
    raw = stability.sg_composite_device(c, "SG1", opts.sg_bus, ...
        find(bus_ids==opts.sg_bus,1), bus_ids, ...
        complex(y0(2*find(bus_ids==opts.sg_bus,1)-1),y0(2*find(bus_ids==opts.sg_bus,1))), emfp);
    sg = emf6_sg_adapter(raw, c.base_values.frequency_Hz, opts.sg_bus);
else
    dae = build_sg_dae(c, pf, opts.sg_bus, char(opts.excitation), opts.sg_H_scale, ...
        opts.sg_X_scale, opts.sg_H, opts.sg_D);
    sg = ibr.padiyar_sg_unit(dae, 1, opts.sg_droop_R);
end

% --- network Thevenin impedance per bus (diagnostic SCR) ------------------
Z = inv(Y);

% --- four switchable IBRs at the remaining generator buses ----------------
nib = numel(opts.ibr_buses);
devs = cell(1,nib); x_ibr0 = cell(1,nib); ibr_bp = zeros(1,nib);
scr_bus = zeros(1,nib); Mbase = zeros(1,nib);
for j = 1:nib
    b = opts.ibr_buses(j); bp = find(bus_ids==b,1);
    if isempty(bp), error('ibr:build_ieee14_switch_system:ibrBus','IBR bus %d not found.',b); end
    V0 = complex(y0(2*bp-1), y0(2*bp));
    P = pf.P_generation(bp); Q = pf.Q_generation(bp);
    if lower(opts.case_profile) == "eecon49_figure4"
        % SOURCE_DEFINED base contract: EECON49-P4 declares one 100-MVA pu
        % base and does not publish separate converter MVA bases.  The Figure-4
        % operating-point injections are dispatch values, not unit ratings.
        % Therefore Imax=1.2 pu means 1.2 pu on the common 100-MVA base for
        % every IBR; inferring Mbase from the initial |S| incorrectly derates
        % the four converters precisely when the SG is disconnected.
        Mb = 100;
    else
        Mb = 100*max(abs(P + 1i*Q), 0.20);             % legacy diagnostic rating inference
    end
    params = struct('Sbase',100,'Mbase',Mb,'fbase',c.base_values.frequency_Hz);
    if lower(opts.case_profile) == "eecon49_figure4"
        % EECON49-P4 parameter table.  The full-state route keeps the
        % source blocks (AC filter, DC link, PLL/VSG, outer voltage/power PI,
        % inner current PI) explicit.  The paper parameter table specifies
        % kp_Idq=0.30 and ki_Idq=4.00.
        params.ibr_model_family = 'eecon49_full';
        % Command/actuation-delay states eq.(20)-(21) are reduced out
        % (v_del=v_cmd): the physical T_d = 1.5/f_sw ~= 0.3 ms (f_sw = 5 kHz) is
        % >300x below the phasor step dt = 0.10 s, so by singular perturbation
        % the fast lag collapses onto its slow manifold. See defect
        % TD-2026-08-12-01 and the device models for the derivation. No Td
        % parameter is passed.
        params.gfl_eecon49 = struct('Lf',0.15,'Rf',0.015,'Cdc',0.10, ...
            'Vdc_ref',1.0,'Imax',1.2,'kpPLL',1.20,'kiPLL',5.00, ...
            'kpP',0.80,'kiP',2.50,'kpQ',0.80,'kiQ',2.50,'kpI',0.30,'kiI',4.00);
        params.gfm_eecon49 = struct('Lf',0.15,'Rf',0.015,'Cdc',0.10, ...
            'Vdc_ref',1.0,'Imax',1.2,'M',0.08,'Dv',20.0, ...
            'tauE',0.05,'kQ',0.25,'kE',8.00,'kpV',1.20,'kiV',4.50, ...
            'kpI',0.30,'kiI',4.00);
        % Dv=20.0: PROJECT_DERIVED islanded grid-forming value.  The frozen
        % design target it meets is a 5 % P-f droop.  In this single-coefficient
        % VSG the same Dv also fixes the swing damping: at the MEASURED
        % synchronising coefficient K = 0.1135..0.1862 pu/rad (full-KCL
        % Schur-reduced SSSA, all-GFM SG-online) Dv=20 gives zeta = 4.22..5.40,
        % i.e. heavily over-damped, so droop and damping cannot both be placed
        % here.  An earlier note in this file quoted zeta ~= 0.81 from an
        % unmeasured K ~= 5 pu/rad estimate; that number was wrong.  The
        % source-printed value is Dv=1.50 (66.7 % droop, zeta = 0.41), verified
        % in docs/text/EECON49_[Nui].pdf p.5 with `pdftotext -layout` -- the PDF
        % is NOT encrypted; only the Read tool cannot render it.  See
        % docs/project/EECON49_GFL_GFM_SOURCE_CONTRACT.md and, for the model
        % that separates the two roles,
        % docs/project/DECOUPLED_GFM_SOURCE_CONTRACT.md.
    end
    d = ibr.SwitchableIbr6(sprintf("IBR%d",b), b, bp, bus_ids, V0, params, P, Q, ...
        index_mode=opts.index_mode, AGSI_up=opts.AGSI_up, AGSI_down=opts.AGSI_down, ...
        T_d_on=opts.T_d_on, T_d_off=opts.T_d_off);
    devs{j} = d; ibr_bp(j) = bp; Mbase(j) = Mb;
    d.ilim = opts.gfm_ilim * (Mb/100);                 % |I| <= i_max x rated (system base)
    d.ilim_mode = char(opts.ilim_mode);
    x_ibr0{j} = d.gfl_dev.equilibrium_initialize(V0, P, Q, struct());
    scr_bus(j) = abs(V0)^2 / (abs(Z(bp,bp)) * max(abs(P+1i*Q),0.20));
end

sys = struct();
sys.classification = 'ASSUMED_DIAGNOSTIC_IEEE14_1SG_4IBR_SWITCH';
sys.sg = sg;
sys.devs = devs;
sys.Y = Y;
sys.bus_ids = bus_ids;
sys.pf = pf;
sys.y0 = y0;
sys.x_sg0 = sg.x0;
sys.x_ibr0 = x_ibr0;
sys.sg_bus = opts.sg_bus;
sys.sg_bus_position = sg.bus_position;
sys.ibr_buses = opts.ibr_buses;
sys.ibr_bus_positions = ibr_bp;
sys.scr_bus = scr_bus;
sys.scr_strong = 20;
sys.load_adm = load_adm;
sys.line_data = c.line_data;
sys.load_buses = bus_ids(abs(pf.P_load(:)).' + abs(pf.Q_load(:)).' > 0);
sys.Mbase = Mbase;
sys.nb = nb;
sys.base = c.base_values;
sys.case_profile = opts.case_profile;
if isfield(c,'eecon49_mapping'), sys.eecon49_mapping = c.eecon49_mapping; end
if isfield(c,'switching_event_contract')
    sys.switching_event_contract = c.switching_event_contract;
end
end

% =========================================================================
function params = build_emf6_override(c, pf, sg_bus, H_direct, D_direct)
% Build the operational EMF6 coefficient/init structs on the tap-aware PF
% operating point.  This is the same coefficient mapping used by
% synchronous_emf6_ssa, isolated here because its standalone network_model
% intentionally omits IEEE transformer taps.
M = c.machines; sc = c.base_values.S_base_MVA/M.base.S_MVA;
R=M.reactances; T=M.time_constants;
machine = struct();
for nm={'Xd','Xdp','Xdpp','Xq','Xqp','Xqpp','Ra'}
    name=nm{1}; machine.(name)=R.(name)*sc;
end
machine.Tpd0=T.Tpd0; machine.Tppd0=T.Tppd0; machine.Tpq0=T.Tpq0; machine.Tppq0=T.Tppq0;
machine.c_d=(machine.Xd-machine.Xdp)/(machine.Xdp-machine.Xdpp);
machine.d_d=(machine.Xd-machine.Xdpp)/(machine.Xdp-machine.Xdpp);
machine.c_q=(machine.Xq-machine.Xqp)/(machine.Xqp-machine.Xqpp);
machine.d_q=(machine.Xq-machine.Xqpp)/(machine.Xqp-machine.Xqpp);
machine.w0=2*pi*c.base_values.frequency_Hz; machine.ng=1;
bp=find(pf.external_bus_ids==sg_bus,1);
V=pf.bus_voltage(bp)*exp(1i*deg2rad(pf.bus_angle_deg(bp)));
S=pf.P_generation(bp)+1i*pf.Q_generation(bp); I=conj(S/V);
delta=angle(V+(machine.Ra+1i*machine.Xq)*I);
[Id,Iq]=to_dq(I,delta); [Vd,Vq]=to_dq(V,delta);
Eqpp=Vq+machine.Ra*Iq+machine.Xdpp*Id;
Edpp=Vd+machine.Ra*Id-machine.Xqpp*Iq;
Eqp=Eqpp+(machine.Xdp-machine.Xdpp)*Id;
Edp=Edpp-(machine.Xqp-machine.Xqpp)*Iq;
Efd=machine.d_d*Eqp-machine.c_d*Eqpp;
Te=Vd*Id+Vq*Iq+machine.Ra*(Id^2+Iq^2);
Hmach=M.units.H; Dmach=M.units.D;
if isfinite(H_direct), Hmach=H_direct/sc; end
if isfinite(D_direct), Dmach=D_direct/sc; end
units=struct('bus_idx',bp,'H_system',Hmach*sc,'D_system',Dmach*sc, ...
    'H_machine',Hmach,'D_machine',Dmach,'id',{{'SG1'}});
init=struct('x0',[delta;0;Eqp;Edp;Eqpp;Edpp], ...
    'Tm',Te,'Efd',Efd,'Id',Id,'Iq',Iq,'ng',1);
params=struct('emf6_machine',machine,'emf6_units',units,'emf6_init',init);
end

function sg = emf6_sg_adapter(dev, fbase, bus_id)
% Adapt the audited composite EMF6 device to the compact mixed TDS ABI.
sg=struct('name','SG1','device_type','sg_emf6','excitation','emf6', ...
    'nx',dev.nx,'bus_position',dev.bus_position,'x0',dev.x0(:),'u0',dev.u0(:), ...
    'par',struct('fbase',fbase),'device',dev);
sg.f=@(x,y) dev.f(0,x,y,dev.u0,struct());
sg.current_injection=@(x,y) dev.current_injection(0,x,y,dev.u0,struct());
sg.electrical_power=@(x,y) dev.electrical_power(0,x,y,dev.u0,struct());
sg.reconstruct=@(x,y) emf6_reconstruct_adapter(dev,x,y,fbase);
sg.reinit=@(V) dev.equilibrium_initialize(V,dev.u0(1),0,struct());
end

function out = emf6_reconstruct_adapter(dev,x,y,fbase)
out=dev.reconstruct(0,x,y,dev.u0,struct());
out.f_hz=fbase*(1+out.omega); out.omega_pu=1+out.omega;
out.Pe=dev.electrical_power(0,x,y,dev.u0,struct());
V=complex(y(2*dev.bus_position-1),y(2*dev.bus_position));
out.Qe=imag(V*conj(dev.current_injection(0,x,y,dev.u0,struct())));
out.Vbus=abs(V);
end

% =========================================================================
function dae = build_sg_dae(c, pf, sg_bus, exc, H_scale, X_scale, H_direct, D_direct)
if nargin < 5 || isempty(H_scale), H_scale = 1.0; end
if nargin < 6 || isempty(X_scale), X_scale = 1.0; end
if nargin < 7 || isempty(H_direct), H_direct = NaN; end
if nargin < 8 || isempty(D_direct), D_direct = NaN; end
% Minimal DAE-struct for ONE Padiyar model-1.1 machine at sg_bus, initialised
% from the power-flow operating point, in the ABI ibr.padiyar_sg_unit expects.
% X_scale multiplies the internal reactances (coupling-strength / electrical-
% distance sweep knob). The terminal V,I,P,Q are fixed by the power flow, so
% the equilibrium is re-derived consistently (delta, Eqp, Edp, Efd adjust;
% Te=P is invariant with Ra=0). X_scale=1.0 reproduces the baseline exactly.
sZ = 100/615; sH = 615/100;                     % 615 MVA machine base -> 100 MVA
Ra=0.0; Xd=0.8979*sZ*X_scale; Xdp=0.2995*sZ*X_scale; Xq=0.646*sZ*X_scale; Xqp=Xq;
Tpd0=7.4; Tpq0=0.033; KA=200; TA=0.02;
H=5.148*sH*H_scale; D=2.0*sH*H_scale; fb=c.base_values.frequency_Hz;
if isfinite(H_direct), H=H_direct; end
if isfinite(D_direct), D=D_direct; end
if ~(isfinite(H) && H>0 && isfinite(D) && D>=0)
    error('ibr:build_ieee14_switch_system:sgHD','SG H must be positive and D non-negative.');
end

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
