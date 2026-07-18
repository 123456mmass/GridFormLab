function [devices, dev_meta] = build_ieee14_ibr_devices(case_data, device_modes, dispatch_MW)
%BUILD_IEEE14_IBR_DEVICES  Real-device builder for IEEE14 1-SG + 4-IBR (Phase 8).
%
%   [DEVICES, DEV_META] = build_ieee14_ibr_devices(CASE_DATA, DEVICE_MODES,
%       DISPATCH_MW) builds the 4 real IBR devices (IBR2@bus2, IBR3@bus3,
%       IBR6@bus6, IBR8@bus8) using +ibr/dual_mode_ibr_model, with PF
%       warm-start V0 per bus and CASE_DEFINED Mbase per IBR.
%
%   SG1 (bus 1) is NOT a device in this list — when online its slack is the
%   PF (bus 1=REF); when tripped, no SG device. This mirrors the Phase 4
%   synthetic fixture contract, but uses REAL +ibr models (not synthetic).
%
%   Inputs:
%     case_data    - the IEEE14 case (case_ieee14_1sg_4ibr_auto_vsg)
%     device_modes - struct array (.device_id, .mode) with mode in
%                    {'gfl','GFM','tripped'} for each IBR
%     dispatch_MW  - struct with per-IBR active-power dispatch (MW, system base)
%
%   Output:
%     devices   - 1x4 struct array conforming to composite_dae ABI
%     dev_meta  - struct with bus_ids, V0_per_bus, Mbase_per_ibr (provenance)
%
%   Mbase (CASE_DEFINED unity-PF nameplate proxy, FROZEN before results):
%     IBR2 = 140 MVA, IBR3 = 100 MVA, IBR6 = 100 MVA, IBR8 = 100 MVA.
%     NOT Pmax-MW proven (nameplate proxy). kappa = Sbase/Mbase applied to
%     REGFM_B1 Eqs.1-3,5 (system base -> inverter base).
%
%   No synthetic fixture, no auto-discovery. Uses sourced dispatch/Mbase
%   from the frozen case contract.
%
%   Source: docs/project/IEEE14_IBR_FROZEN_CONTRACT.md;
%           +cases/case_ieee14_1sg_4ibr_auto_vsg.m (dispatch contract).

arguments
    case_data struct
    device_modes struct
    dispatch_MW struct
end

Sbase = 100.0;   % MVA, system base (frozen)

% --- Frozen Mbase per IBR (CASE_DEFINED unity-PF nameplate proxy) ----------
Mbase_map = struct('IBR2', 140.0, 'IBR3', 100.0, 'IBR6', 100.0, 'IBR8', 100.0);

% --- IBR -> bus map (from case_data.devices) ------------------------------
ibr_ids = {'IBR2','IBR3','IBR6','IBR8'};
bus_map = struct();
for k = 1:numel(ibr_ids)
    did = ibr_ids{k};
    bus_map.(did) = case_data.devices.(did).bus;
end

% --- PF warm-start (in-house Newton) for V0 per bus ------------------------
% This mirrors composite_dae's internal PF so device constructors get the
% correct complex V0 (angle + magnitude) for initialization. The PF is run
% on the unmodified MATPOWER14 network (bus 1 = REF, V=1.06).
pf = pfsolver.powerflow_newton_raphson(case_data, struct('verbose',false, ...
    'plot_results',false,'max_iter',50,'tolerance',1e-10,'enforce_q_limits',false));
if ~pf.converged
    error('ibr:build_ieee14_ibr_devices:powerFlow', ...
        'In-house Newton PF did not converge for IEEE14 warm-start.');
end
bus_ids = pf.external_bus_ids(:);
V0_complex = pf.bus_voltage(:) .* exp(1i * deg2rad(pf.bus_angle_deg(:)));

% --- Build device modes lookup --------------------------------------------
mode_lookup = struct();
family_lookup = struct();
for k = 1:numel(device_modes)
    mode_lookup.(device_modes(k).device_id) = device_modes(k).mode;
    if isfield(device_modes(k),'gfl_family') && ~isempty(device_modes(k).gfl_family)
        family_lookup.(device_modes(k).device_id) = char(device_modes(k).gfl_family);
    else
        family_lookup.(device_modes(k).device_id) = '';
    end
end

% --- Build the 4 real IBR devices ------------------------------------------
devices = struct([]);
for k = 1:numel(ibr_ids)
    did = ibr_ids{k};
    bus = bus_map.(did);
    bp = find(bus_ids == bus, 1);
    if isempty(bp)
        error('ibr:build_ieee14_ibr_devices:badBus', ...
            'IBR %s bus %d not found in network bus_ids.', did, bus);
    end
    V0 = V0_complex(bp);
    Mbase = Mbase_map.(did);
    params = struct('Mbase', Mbase);
    fam = family_lookup.(did);
    if ~isempty(fam)
        params.gfl_family = fam;   % construction-time GFL family selection
    end
    P_ref_pu = dispatch_MW.(did) / Sbase;   % MW -> pu (system base)
    Q_ref_pu = 0.0;                          % unity PF default
    V_ref_pu = abs(V0);                      % voltage setpoint = PF magnitude
    mode = mode_lookup.(did);
    dev = ibr.dual_mode_ibr_model(string(did), bus, bp, bus_ids(:)', V0, params, ...
        P_ref_pu, Q_ref_pu, V_ref_pu, string(mode));
    if k == 1
        devices = dev;
    else
        devices(k) = dev;
    end
end

% --- Provenance metadata ---------------------------------------------------
dev_meta = struct();
dev_meta.bus_ids = bus_ids(:)';
dev_meta.V0_per_bus = V0_complex;
dev_meta.Mbase_per_ibr = Mbase_map;
dev_meta.Sbase = Sbase;
dev_meta.kappa_per_ibr = struct('IBR2', Sbase/Mbase_map.IBR2, ...
    'IBR3', Sbase/Mbase_map.IBR3, 'IBR6', Sbase/Mbase_map.IBR6, ...
    'IBR8', Sbase/Mbase_map.IBR8);
dev_meta.source = 'Real +ibr/dual_mode_ibr_model devices; Mbase=CASE_DEFINED nameplate proxy';
dev_meta.no_synthetic = true;
end
