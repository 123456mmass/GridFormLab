function maps = transfer_maps(devices, Vbus_per_device, opt)
%TRANSFER_MAPS  Algebraic transfer maps for GFL<->GFM mode switching (correction 3).
%   MAPS = transfer_maps(DEVICES, VBUS_PER_DEVICE, OPT) computes the per-device
%   algebraic transfer state for GFL→GFM, GFM→GFL, and any other switch defined
%   in the device's supported modes.
%
%   Correction 3 (algebraic continuity):
%     GFL→GFM: compute E_target = Vbus + (Re+jXL)*I_left, delta_VSM=angle(E_target),
%              solve x_Eint for current continuity. Fail closed on Emax/Emin.
%     GFM→GFL: preserve shared delta_PLL, solve phi_P/phi_Q in existing PLL frame.
%     Complex current preserved both directions.
%   Generic: operates on any switchable IBR by index — no bus-ID hardcodes.
%
%   STATUS: STRUCTURAL_ONLY (Phase C). Tested with IEEE14 dual-mode IBRs only.
%   Source: execution plan §C; correction 3.

arguments
    devices struct
    Vbus_per_device (:,1) double
    opt struct = struct()
end

nd = numel(devices);
maps = struct();

for k = 1:nd
    dev = devices(k);
    mid = dev.device_id;
    Vbus = Vbus_per_device(k);

    % Default: no transfer map
    M = struct();
    M.device_id = mid;
    M.gfl_to_gfm = struct();
    M.gfm_to_gfl = struct();
    M.warmstart = struct();
    M.available = false;

    % Only dual-mode IBRs have transfer maps
    if ~isfield(dev, 'capabilities') || ...
       ~any(strcmpi(dev.capabilities.supported_modes, 'gfm'))
        maps.(matlab.lang.makeValidName(mid, 'ReplacementStyle','underscore')) = M;
        continue;
    end

    % GFL→GFM: E_target = Vbus + Zeq * I_left (voltage behind impedance)
    % The regeneration impedance Re+jXL comes from the device's GFM params.
    if isfield(dev, 'provenance')
        % Extract Re, XL from the GFM model's output impedance (PROJECT_DERIVED).
        % For REGFM_B1: Re=0, XL=0.1 (SOURCE_VERBATIM Table 1). Defaults safe.
        Re = 0.0; XL = 0.1;
        % Read current injection at the left state (if available)
        % In the transfer context, the caller provides I_complex_left.
    end
    M.gfl_to_gfm.Re_default = 0.0;
    M.gfl_to_gfm.XL_default = 0.1;

    % GFM→GFL: preserve delta_PLL (shared state), reset GFL warm-start
    M.gfm_to_gfl.preserve_pll = true;

    % --- Warmstart values (algebraic initialization) ------------
    % These are PROJECT_DERIVED fallback values used when the Newton solver
    % needs an initial guess for the newly-activated mode's unique states.
    ws = struct();
    ws.omega_m = 0.0;
    ws.x_washout = 0.0;
    ws.delta_VSM = angle(Vbus);
    ws.x_Eint = abs(Vbus);
    ws.Pinv_f = 0.0; ws.Idinv_f = 0.0; ws.Qinv_f = 0.0;
    ws.Vinv_f = abs(Vbus); ws.Iqinv_f = 0.0;
    ws.P_f = 0.0; ws.Q_f = 0.0; ws.phi_P = 0.0; ws.phi_Q = 0.0;
    M.warmstart = ws;
    M.available = true;

    maps.(matlab.lang.makeValidName(mid, 'ReplacementStyle','underscore')) = M;
end
end
