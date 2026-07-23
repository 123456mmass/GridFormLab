function sys = build_padiyar_switch_system(opts)
%BUILD_PADIYAR_SWITCH_SYSTEM  Padiyar two-area network with 1 SG (bus 11) and 3
%   switchable GFL/GFM IBRs (buses 1,2,12), for the AGSI/AGSI++ mode-switch study.
%
%   sys = ibr.build_padiyar_switch_system(Name=Value) returns a struct holding
%   the SG unit, the three ibr.SwitchableIbr6 devices, the 10-bus admittance Y
%   (lines + shunts + constant-impedance loads, from stability.padiyar_model11_dae),
%   the equilibrium state slices, and bus bookkeeping. The full 4-machine DAE is
%   used only to obtain the audited Y-bus, the in-house power flow and the SG
%   parameters; the SG dynamics are evaluated by ibr.padiyar_sg_unit.
%
%   Name=Value: index_mode ("agsi_pp"|"agsi"), AGSI_up, AGSI_down, T_d_on, T_d_off.
%   Classification: ASSUMED_DIAGNOSTIC study builder; project code only.

arguments
    opts.index_mode (1,1) string = "agsi_pp"
    opts.AGSI_up (1,1) double = 0.65
    opts.AGSI_down (1,1) double = 0.35
    opts.T_d_on (1,1) double = 0.0
    opts.T_d_off (1,1) double = 0.0
    opts.sg_bus (1,1) double = 11
    opts.ibr_buses (1,:) double = [1 2 12]
    opts.sg_droop_R (1,1) double = 0.05   % SG primary-governor droop (pu/pu); Inf disables
    opts.gfm_ilim (1,1) double = 1.2      % GFM/GFL current limit (x rated); Inf disables
    opts.excitation (1,1) string = "avr"  % Padiyar two-area default: "avr" (5-state, needed for reclose stability); "manual"=4-state NO AVR
end
pf_init_paths();

c = cases.case_padiyar_two_area_4m_avr();
dae = stability.padiyar_model11_dae(c, struct('excitation',char(opts.excitation)));   % 4 machines (passes)
pf = dae.pf; Y = dae.Ynet; bus_ids = dae.bus_ids(:).';
y0 = dae.y0;

% --- SG unit at the chosen SG bus -----------------------------------------
kSG = find(dae.gen_buses==opts.sg_bus,1);
if isempty(kSG)
    error('ibr:build_padiyar_switch_system:sgBus','SG bus %d not a machine bus.',opts.sg_bus);
end
sg = ibr.padiyar_sg_unit(dae, kSG, opts.sg_droop_R);

% --- network Thevenin impedance per bus (for the AGSI++ grid-strength term) -
Z = inv(Y);   %#ok<MINV>  small 10x10, used for a diagnostic SCR only

% --- three switchable IBRs at the remaining generator buses ----------------
nib = numel(opts.ibr_buses);
devs = cell(1,nib); x_ibr0 = cell(1,nib); ibr_bp = zeros(1,nib);
scr_bus = zeros(1,nib); Mbase = zeros(1,nib);
for j = 1:nib
    b = opts.ibr_buses(j); bp = find(bus_ids==b,1);
    if isempty(bp), error('ibr:build_padiyar_switch_system:ibrBus','IBR bus %d not found.',b); end
    V0 = complex(y0(2*bp-1), y0(2*bp));
    P = pf.P_generation(bp); Q = pf.Q_generation(bp);
    Mb = 100*abs(P + 1i*Q);                                  % machine rating (MVA)
    params = struct('Sbase',100,'Mbase',Mb,'fbase',dae.base.frequency_Hz);
    d = ibr.SwitchableIbr6(sprintf("IBR%d",b), b, bp, bus_ids, V0, params, P, Q, ...
        index_mode=opts.index_mode, AGSI_up=opts.AGSI_up, AGSI_down=opts.AGSI_down, ...
        T_d_on=opts.T_d_on, T_d_off=opts.T_d_off);
    devs{j} = d; ibr_bp(j) = bp; Mbase(j) = Mb;
    % converter current limit on the SYSTEM base: |I| <= i_max x rated, with the
    % rating = Mb/Sbase = |S_dispatch| pu. Inactive at the equilibrium
    % (|I0| ~ |S| < i_max|S|), so the operating point is unchanged; it only caps
    % the low-voltage over-current runaway. Inf => no limit.
    d.ilim = opts.gfm_ilim * abs(P + 1i*Q);
    x_ibr0{j} = d.gfl_dev.equilibrium_initialize(V0, P, Q, struct());
    % Diagnostic per-IBR SCR from the passive-network Thevenin at this bus
    % (used post-trip; pre-trip the SG anchors the grid so SCR is treated strong).
    scr_bus(j) = abs(V0)^2 / (abs(Z(bp,bp)) * abs(P+1i*Q));
end

sys = struct();
sys.classification = 'ASSUMED_DIAGNOSTIC_PADIYAR_1SG_3GFL_SWITCH';
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
sys.scr_bus = scr_bus;      % post-trip diagnostic SCR per IBR
sys.scr_strong = 20;        % SG-online (anchored) SCR value => J_SCR ~ 0
% Per-bus constant-impedance load admittance (for a load-step disturbance) and
% the load buses, from the audited network model.
sys.load_adm = (dae.load.P(:) - 1i*dae.load.Q(:))./(dae.load.V0(:).^2);
sys.load_buses = bus_ids(abs(dae.load.P(:)).' + abs(dae.load.Q(:)).' > 0);
sys.Mbase = Mbase;
sys.nb = numel(bus_ids);
sys.base = dae.base;
end
