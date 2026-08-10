classdef SwitchableIbr6 < handle
%SWITCHABLEIBR6  Two-mode (GFL<->GFM) IBR whose switching is governed by
%   the AGSI equation (an always-evaluated reference equation), bumpless and
%   BIDIRECTIONAL.
%
%   obj = ibr.SwitchableIbr6(DEVICE_ID, BUS_ID, BUS_POSITION, BUS_IDS, V0,
%       PARAMS, P_REF, Q_REF, Name=Value) wraps the selected branch models as
%   the SINGLE SOURCE OF TRUTH for the equations.  The legacy default is the
%   reduced-6 pair.  An EECON49 profile can request the source-mapped full-state
%   pair with params.ibr_model_family='eecon49_full':
%       GFL -> ibr.gfl_eecon49_full_model, GFM -> ibr.gfm_eecon49_full_model.
%   This class dispatches the ACTIVE branch, evaluates the switching EQUATION,
%   and performs a current-continuous ("bumpless") transfer in either direction.
%   Both branches in one object have the same fixed state dimension; a switch
%   re-initialises those slots to the target-branch equilibrium at the
%   instantaneous terminal (V,P,Q).
%
%   ================= SWITCHING EQUATION: AGSI ==============================
%   The switch decision ALWAYS compares a single reference equation, the
%   Adaptive Grid Stability Index (AGSI), against hysteresis thresholds. AGSI is
%   a weighted sum of normalised terminal deviations (all measurable at the PCC):
%
%       AGSI = w_V*J_V + w_f*J_f + w_R*J_R + w_P*J_P
%              + w_SCR*J_SCR + w_lock*J_lock + w_GRA*J_GRA
%       J_V = |V   - V_ref| / dV_base        (voltage deviation)
%       J_f = |f   - f0    | / df_base        (frequency deviation)
%       J_R = |df/dt       | / dR_base        (rate of change of frequency)
%       J_P = |P_ref - P   | / dP_base        (active-power tracking error)
%       J_SCR = max(0, 3/SCR - 1)              (weak-grid stress)
%       J_lock = |v_q| / dvq_base              (PLL loss-of-lock stress)
%       J_GRA = 1-GRA                          (missing-reference stress)
%       AGSI = sat_[0,1](sum_i w_i*J_i)         (bounded decision index)
%       sum(w_i) = 1
%
%   DEFAULT SWITCHING LOGIC (hysteresis + dwell):
%       GFL -> GFM : AGSI >= AGSI_up, held >= T_d_on
%       GFM -> GFL : AGSI <  AGSI_down, held >= T_d_off
%   GRA is one weighted AGSI++ input, not a hard command.  The optional
%   gra_override=true route adds the legacy hard GRA rule.  When latch=true the
%   switch is one-way (GFL->GFM only).
%
%   INDEX MODES (presets; caller-passed w_* overrides the preset, sum==1 enforced):
%     'agsi'    - plain four-term AGSI, EECON49-P4 sec 4.1 source-guided:
%                 [w_V w_f w_R w_P] = [0.30 0.30 0.25 0.15], raw RoCoF.
%     'agsi_pp' - severity AGSI, PROJECT_DERIVED two-term index and the
%                 implemented switching supervisor for the IEEE14 go/no-go study:
%                 severity S = sat_[0,1](0.5*J_V + 0.5*J_f) with bases
%                 dV_base=0.10 pu, df_base=0.50 Hz.  The 0.30:0.30 V:f ratio of
%                 EECON49-P4 renormalised to sum 1 gives 0.5:0.5.  The five
%                 demoted stresses (J_R, J_P, J_SCR, J_lock, J_GRA) carry zero
%                 weight and remain diagnostics only; they are not silently
%                 asserted as mode-change gates.  System-level event authority,
%                 transfer-map validity, reference ownership, and right-limit KCL
%                 remain separate contracts (an equal 1/7 average would let one
%                 large J_V be diluted by the mostly-zero other terms).
%                 RoCoF stays low-pass filtered to reject the one-sample spike
%                 inherited from the former AGSI++ default.
%
%   SOURCE / CLASSIFICATION: the four-term plain AGSI route is source-guided.
%   The AGSI++ severity index is PROJECT_DERIVED from the EECON49-P4 V:f
%   severity ratio (0.30:0.30) renormalised onto the two-term base.  The
%   EECON49 source case supplies data/events only; this supervisor is not a
%   reproduction of the paper's Bayesian-optimisation method.  The wrapped
%   GFL/GFM branch equations keep their own documented provenance.
%
%   Defaults (EECON49-P4 sec 4.1): w=[0.30,0.30,0.25,0.15] (plain);
%   agsi_pp severity w=[0.50,0.50,0,0,0,0,0];
%   bases dV=0.10 pu, df=0.50 Hz, dR=1.00 Hz/s, dP=0.20 pu;
%   AGSI_up=0.65 (Gamma_on), AGSI_down=0.35 (Gamma_off);
%   T_d_on=0.10 s, T_d_off=1.00 s; V_ref=1.0; GRA=1 (infinite bus present).

    properties
        device_id       % char device name
        bus_id          % external bus id (double)
        bus_position    % network state index (into y)
        bus_ids         % row vector of bus ids
        f0 = 60         % base/nominal frequency [Hz]
        gfl_dev         % struct from ibr.gfl_reduced6_model (equation SOT)
        gfm_dev         % struct from ibr.gfm_reduced6_model (equation SOT)
        mode = 'gfl'    % active mode: 'gfl' | 'GFM'
        % --- AGSI weights (sum = 1) ----------------------------------------
        w_V = 0.30
        w_f = 0.30
        w_R = 0.25
        w_P = 0.15
        w_SCR = 0.0     % AGSI++ grid-strength weight (0 for plain AGSI)
        w_lock = 0.0    % AGSI++ PLL loss-of-lock weight (0 for plain AGSI)
        w_GRA = 0.0     % AGSI++ missing-reference weight; J_GRA=1-GRA
        % --- AGSI normalisation bases --------------------------------------
        dV_base = 0.10  % pu
        df_base = 0.50  % Hz
        dR_base = 1.00  % Hz/s
        dP_base = 0.20  % pu
        dvq_base = 0.10 % J_lock normalisation (|v_q| pu)
        V_ref = 1.0     % nominal PCC voltage magnitude for J_V [pu]
        V_ref_per_bus = zeros(0,2) % [external bus_id, healthy PF |V|]; when non-empty J_V uses the unique matching row
        % --- AGSI++ enhancements -------------------------------------------
        index_mode = 'agsi'    % 'agsi' (EECON49) | 'agsi_pp' (AGSI++)
        filtered_rocof = false % AGSI++ uses a low-pass-filtered RoCoF
        rocof_tau = 0.05       % RoCoF low-pass time constant [s]
        SCR_crit = 3.0         % weak-grid SCR threshold for J_SCR
        grid_scr = 1e6         % local short-circuit ratio (set by the driver)
        ilim = inf             % converter current-magnitude limit (system pu); inf=off
        ilim_mode = 'clamp'    % 'clamp' (hard magnitude clamp, default) | 'vi' (soft virtual-impedance-style rolloff)
        vi_soft = 0.25         % 'vi' extra headroom fraction: saturates near ilim*(1+vi_soft)
        rocof_filt = NaN       % filtered-RoCoF state
        % --- switching thresholds / dwell / reference availability ---------
        AGSI_up = 0.65    % Gamma_on : GFL->GFM up-line
        AGSI_down = 0.35  % Gamma_off: GFM->GFL down-line (< AGSI_up)
        T_d_on = 0.10     % dwell [s] for GFL->GFM
        T_d_off = 1.00    % dwell [s] for GFM->GFL
        GRA = 1           % grid reference availability (1=present, 0=lost)
        gra_override = false % false (default) => switching is PURELY index-driven
                          % (only IBRs whose AGSI crosses the ref line switch);
                          % true => EECON49 hard rule: GRA=0 forces GFM and
                          % GRA=1 is required to return to GFL.
        latch = false     % true => one-way (GFL->GFM only)
        u               % active input [P_ref; Q_ref]
        P_ref0          % constructed P_ref
        Q_ref0          % constructed Q_ref
        % --- runtime bookkeeping -------------------------------------------
        switched = false
        n_switch = 0
        last_switch_time = NaN
        mode_entry_time = 0
        up_since = NaN    % first time the GFL->GFM condition became true
        down_since = NaN  % first time the GFM->GFL condition became true
        f_prev = NaN      % previous-step frequency (for df/dt)
        t_prev = NaN      % previous-step time
        last_index = 0    % last AGSI value
    end

    methods
        function obj = SwitchableIbr6(device_id, bus_id, bus_position, ...
                bus_ids, V0, params, P_ref, Q_ref, opts)
            arguments
                device_id
                bus_id (1,1) double
                bus_position (1,1) double
                bus_ids (1,:) double
                V0 (1,1) double
                params struct
                P_ref (1,1) double
                Q_ref (1,1) double
                opts.index_mode (1,1) string = "agsi"
                opts.w_V (1,1) double = NaN
                opts.w_f (1,1) double = NaN
                opts.w_R (1,1) double = NaN
                opts.w_P (1,1) double = NaN
                opts.w_SCR (1,1) double = NaN
                opts.w_lock (1,1) double = NaN
                opts.w_GRA (1,1) double = NaN
                opts.filtered_rocof (1,1) double = -1
                opts.rocof_tau (1,1) double = 0.05
                opts.SCR_crit (1,1) double = 3.0
                opts.dV_base (1,1) double = 0.10
                opts.df_base (1,1) double = 0.50
                opts.dR_base (1,1) double = 1.00
                opts.dP_base (1,1) double = 0.20
                opts.dvq_base (1,1) double = 0.10
                opts.V_ref (1,1) double = 1.0
                opts.AGSI_up (1,1) double = 0.65
                opts.AGSI_down (1,1) double = 0.35
                opts.T_d_on (1,1) double = 0.10
                opts.T_d_off (1,1) double = 1.00
                opts.GRA (1,1) double = 1
                opts.gra_override (1,1) logical = false
                opts.latch (1,1) logical = false
                opts.f0 (1,1) double = 60
                opts.V_ref_per_bus double = []
            end
            if ~isfinite(V0) || abs(V0) <= 0
                error('ibr:SwitchableIbr6:badV0','V0 must be finite nonzero.');
            end
            mode = lower(char(opts.index_mode));
            if ~ismember(mode,{'agsi','agsi_pp'})
                error('ibr:SwitchableIbr6:mode','index_mode must be "agsi" or "agsi_pp".');
            end
            % Mode presets (weights sum to 1).  'agsi_pp' is the implemented
            % two-term severity index [V f | R P SCR lock GRA] with a filtered
            % RoCoF diagnostic; caller-passed w_* overrides the preset.
            if strcmp(mode,'agsi_pp')
                defw = [0.5 0.5 0 0 0 0 0];   % severity: J_V+J_f only (0.30:0.30 renormalised)
                deffilt = true;
            else
                defw = [0.30 0.30 0.25 0.15 0.00 0.00 0.00];
                deffilt = false;
            end
            uw = [opts.w_V opts.w_f opts.w_R opts.w_P opts.w_SCR opts.w_lock opts.w_GRA];
            rw = defw; ok = ~isnan(uw); rw(ok) = uw(ok);
            wv = rw(1); wf = rw(2); wr = rw(3); wp = rw(4); ws = rw(5); wl = rw(6); wg = rw(7);
            if opts.filtered_rocof < 0
                filt = deffilt;
            else
                filt = logical(opts.filtered_rocof);
            end
            if opts.AGSI_down >= opts.AGSI_up
                error('ibr:SwitchableIbr6:hysteresis', ...
                    'AGSI_down (%.4g) must be < AGSI_up (%.4g) for a hysteresis band.', ...
                    opts.AGSI_down, opts.AGSI_up);
            end
            wsum = wv + wf + wr + wp + ws + wl + wg;
            if abs(wsum - 1) > 1e-9
                error('ibr:SwitchableIbr6:weights', ...
                    'AGSI weights must sum to 1 (got %.6g).', wsum);
            end
            if any([opts.dV_base,opts.df_base,opts.dR_base,opts.dP_base,opts.dvq_base] <= 0)
                error('ibr:SwitchableIbr6:bases','AGSI normalisation bases must be positive.');
            end
            obj.device_id = char(device_id);
            obj.index_mode = mode;
            obj.filtered_rocof = filt;
            obj.rocof_tau = opts.rocof_tau;
            obj.SCR_crit = opts.SCR_crit;
            obj.dvq_base = opts.dvq_base;
            obj.w_SCR = ws; obj.w_lock = wl; obj.w_GRA = wg;
            obj.bus_id = bus_id;
            obj.bus_position = bus_position;
            obj.bus_ids = bus_ids(:).';
            obj.f0 = opts.f0;
            obj.w_V = wv; obj.w_f = wf; obj.w_R = wr; obj.w_P = wp;
            obj.dV_base = opts.dV_base; obj.df_base = opts.df_base;
            obj.dR_base = opts.dR_base; obj.dP_base = opts.dP_base;
            obj.V_ref = opts.V_ref;
            if ~isempty(opts.V_ref_per_bus)
                refs = opts.V_ref_per_bus;
                if ~isreal(refs) || size(refs,2)~=2 || any(~isfinite(refs(:))) || ...
                        any(refs(:,2)<=0) || numel(unique(refs(:,1)))~=size(refs,1)
                    error('ibr:SwitchableIbr6:invalidVRefPerBus', ...
                        ['V_ref_per_bus must be an N-by-2 finite real table ' ...
                         '[external bus_id, positive healthy |V|] with unique bus IDs.']);
                end
                obj.V_ref_per_bus = refs;
            end
            obj.AGSI_up = opts.AGSI_up;
            obj.AGSI_down = opts.AGSI_down;
            obj.T_d_on = opts.T_d_on;
            obj.T_d_off = opts.T_d_off;
            obj.GRA = opts.GRA;
            obj.gra_override = opts.gra_override;
            obj.latch = opts.latch;
            obj.P_ref0 = P_ref;
            obj.Q_ref0 = Q_ref;
            E_ref=obj.V_ref;
            if ~isempty(obj.V_ref_per_bus)
                ir=find(obj.V_ref_per_bus(:,1)==obj.bus_id,1);
                E_ref=obj.V_ref_per_bus(ir,2);
            end
            obj.u = [P_ref; Q_ref; E_ref];
            full_family = isfield(params,'ibr_model_family') && ...
                strcmpi(string(params.ibr_model_family),'eecon49_full');
            if full_family
                obj.gfl_dev = ibr.gfl_eecon49_full_model(string(device_id), bus_id, ...
                    bus_position, bus_ids, V0, params, P_ref, Q_ref);
                obj.gfm_dev = ibr.gfm_eecon49_full_model(string(device_id), bus_id, ...
                    bus_position, bus_ids, V0, params, P_ref, Q_ref, E_ref);
            else
                obj.gfl_dev = ibr.gfl_reduced6_model(string(device_id), bus_id, ...
                    bus_position, bus_ids, V0, params, P_ref, Q_ref);
                obj.gfm_dev = ibr.gfm_reduced6_model(string(device_id), bus_id, ...
                    bus_position, bus_ids, V0, params, P_ref, Q_ref);
            end
            if obj.gfl_dev.nx ~= obj.gfm_dev.nx
                error('ibr:SwitchableIbr6:nx','GFL/GFM branches must share one state dimension.');
            end
            obj.mode = 'gfl';
        end

        function d = active_dev(obj)
            if strcmp(obj.mode,'gfl')
                d = obj.gfl_dev;
            else
                d = obj.gfm_dev;
            end
        end

        function n = nx(obj)
            n = obj.gfl_dev.nx;
        end

        function x0 = x0_gfl(obj)
            x0 = obj.gfl_dev.x0(:);
        end

        function dx = f(obj, x, y)
            d = obj.active_dev();
            dx = d.f(0, x, y, obj.branch_input(d), struct());
        end

        function I = current_injection(obj, x, y)
            d = obj.active_dev();
            I = d.current_injection(0, x, y, obj.branch_input(d), struct());
            m = abs(I);
            if isfinite(obj.ilim) && m > obj.ilim
                if strcmpi(obj.ilim_mode,'vi')
                    % Virtual-impedance-equivalent SOFT current limit: above ilim
                    % the excess is smoothly rolled off (C1-continuous, inactive
                    % below ilim so the equilibrium is unchanged), saturating near
                    % ilim*(1+vi_soft). Emulates the current-limiting effect of an
                    % adaptive virtual impedance without altering the shared
                    % reduced-6 model dynamics (angle preserved).
                    hd = obj.ilim*max(obj.vi_soft,1e-6);
                    m_lim = obj.ilim + hd*tanh((m-obj.ilim)/hd);
                    I = I*(m_lim/m);
                else   % 'clamp' : hard magnitude clamp (angle preserved)
                    I = obj.ilim*I/m;
                end
            end
        end

        function Pe = electrical_power(obj, x, y)
            d = obj.active_dev();
            Pe = d.electrical_power(0, x, y, obj.branch_input(d), struct());
        end

        function rec = reconstruct(obj, x, y)
            d = obj.active_dev();
            rec = d.reconstruct(0, x, y, obj.branch_input(d), struct());
        end

        function [agsi, parts] = compute_agsi(obj, x, y, t, do_update)
            %COMPUTE_AGSI  Evaluate the AGSI switching equation at (x,y,t).
            %   DO_UPDATE (default false) advances the df/dt memory; only the
            %   switching supervisor call sets it true so recording calls do not
            %   corrupt the one-per-step RoCoF estimate.
            if nargin < 4, t = NaN; end
            if nargin < 5, do_update = false; end
            bp = obj.bus_position;
            if numel(y) < 2*bp
                error('ibr:SwitchableIbr6:badY','y too short for bus_position %d.',bp);
            end
            rec = obj.reconstruct(x, y);
            Vmag = abs(complex(y(2*bp-1), y(2*bp)));
            f_hz = rec.f_hz;
            % Raw numerical RoCoF from the previous accepted sample.
            have_prev = ~(isnan(obj.f_prev) || isnan(obj.t_prev) || ~(t > obj.t_prev));
            if have_prev
                dt_step = t - obj.t_prev;
                rocof_raw = (f_hz - obj.f_prev)/dt_step;
            else
                dt_step = NaN;
                rocof_raw = 0;
            end
            % AGSI++ : low-pass-filtered RoCoF (rejects the one-sample spike that
            % causes no-dwell chattering). Plain AGSI uses the raw value.
            if obj.filtered_rocof
                if isnan(obj.rocof_filt)
                    rf = rocof_raw;
                elseif have_prev
                    a = min(1, dt_step/obj.rocof_tau);
                    rf = obj.rocof_filt + a*(rocof_raw - obj.rocof_filt);
                else
                    rf = obj.rocof_filt;
                end
                rocof_used = rf;
            else
                rf = rocof_raw;
                rocof_used = rocof_raw;
            end
            P = rec.Pe;
            P_ref = obj.u(1);
            % --- baseline sub-indices --------------------------------------
            % J_V uses the healthy per-bus PF |V| when V_ref_per_bus is
            % provided (the network's achievable operating point, not a flat 1.0)
            % -- this is what lets an index-driven supervisor see a "healthy"
            % bus in steady state and release it back to GFL.
            vref = obj.V_ref;
            if ~isempty(obj.V_ref_per_bus)
                ip2 = find(obj.V_ref_per_bus(:,1)==obj.bus_id);
                if numel(ip2)~=1
                    error('ibr:SwitchableIbr6:missingVRefForBus', ...
                        'V_ref_per_bus must contain exactly one row for bus %g.',obj.bus_id);
                end
                vref = obj.V_ref_per_bus(ip2,2);
            end
            J_V = abs(Vmag - vref)/obj.dV_base;
            J_f = abs(f_hz - obj.f0)/obj.df_base;
            J_R = abs(rocof_used)/obj.dR_base;
            J_P = abs(P_ref - P)/obj.dP_base;
            % --- AGSI++ sub-indices (weights are 0 for plain AGSI) ----------
            % J_SCR: grid-strength stress, rises as the local SCR falls below the
            %   weak-grid threshold (root cause of GFL weak-grid instability).
            if obj.w_SCR > 0
                J_SCR = max(0, obj.SCR_crit/max(obj.grid_scr,1e-9) - 1);
            else
                J_SCR = 0;
            end
            % J_lock: PLL loss-of-lock proxy = |v_q| (GFL) or |v_gq| (GFM).
            if obj.w_lock > 0
                if isfield(rec,'v_q')
                    vq = abs(rec.v_q);
                elseif isfield(rec,'v_gq')
                    vq = abs(rec.v_gq);
                else
                    vq = 0;
                end
                J_lock = vq/obj.dvq_base;
            else
                J_lock = 0;
            end
            % J_GRA: binary missing-reference stress. GRA=1 means that an
            % online SG or at least one committed GFM supplies a grid reference.
            J_GRA = double(obj.GRA == 0);
            agsi_raw = obj.w_V*J_V + obj.w_f*J_f + obj.w_R*J_R + obj.w_P*J_P ...
                 + obj.w_SCR*J_SCR + obj.w_lock*J_lock + obj.w_GRA*J_GRA;
            % The supervisor publishes and compares a normalized decision
            % index.  Retain the raw weighted stress only as a diagnostic.
            agsi = min(1,max(0,agsi_raw));
            parts = struct('J_V',J_V,'J_f',J_f,'J_R',J_R,'J_P',J_P, ...
                'J_SCR',J_SCR,'J_lock',J_lock,'J_GRA',J_GRA,'GRA',obj.GRA, ...
                'raw_total',agsi_raw,'bounded_total',agsi, ...
                'rocof',rocof_used,'rocof_raw',rocof_raw, ...
                'Vmag',Vmag,'f_hz',f_hz,'P',P,'P_ref',P_ref,'scr',obj.grid_scr);
            if do_update
                obj.f_prev = f_hz;
                obj.t_prev = t;
                obj.rocof_filt = rf;
            end
            obj.last_index = agsi;
        end

        function J = compute_index(obj, x, y, t)
            %COMPUTE_INDEX  AGSI value WITHOUT advancing the RoCoF memory
            %   (safe for recording/plotting; the supervisor owns the update).
            if nargin < 4, t = NaN; end
            J = obj.compute_agsi(x, y, t, false);
        end

        function Jref = reference_up(obj, ~, ~, ~)
            %REFERENCE_UP  Up-line reference (Gamma_on) of the AGSI equation.
            Jref = obj.AGSI_up;
        end

        function Jdn = reference_down(obj, ~, ~, ~)
            %REFERENCE_DOWN  Down-line reference (Gamma_off) of the AGSI equation.
            Jdn = obj.AGSI_down;
        end

        function [x_new, did_switch, info] = maybe_switch(obj, x, y, t)
            %MAYBE_SWITCH  Evaluate the AGSI switching equation and, if a
            %   threshold is crossed and held for the dwell, transfer bumplessly.
            if nargin < 4, t = NaN; end
            did_switch = false;
            x_new = x;
            [agsi, parts] = obj.compute_agsi(x, y, t, true);   % owns RoCoF update
            info = struct('J',agsi,'J_ref',obj.AGSI_up,'J_down',obj.AGSI_down, ...
                'parts',parts,'direction',"none",'new_mode',string(obj.mode), ...
                'triggered',false,'I_left',NaN,'I_right',NaN,'P',NaN,'Q',NaN,'V',NaN);

            if strcmp(obj.mode,'gfl')
                if obj.gra_override
                    cond_up = (agsi >= obj.AGSI_up) || (obj.GRA == 0);
                else
                    cond_up = (agsi >= obj.AGSI_up);   % pure index-driven
                end
                if cond_up
                    if isnan(obj.up_since), obj.up_since = t; end
                else
                    obj.up_since = NaN;
                end
                if ~isnan(obj.up_since) && (t - obj.up_since) >= obj.T_d_on
                    [x_new, info] = obj.transfer_to(x, y, t, 'GFM', info);
                    did_switch = true;
                end
                return;
            end

            % ---- currently GFM ----------------------------------------------
            if obj.latch
                return;
            end
            if obj.gra_override
                cond_down = (agsi < obj.AGSI_down) && (obj.GRA == 1);
            else
                cond_down = (agsi < obj.AGSI_down);   % pure index-driven
            end
            if cond_down
                if isnan(obj.down_since)
                    obj.down_since = t;
                    % Q-restore before release: return the GFM to the healthy
                    % pre-fault dispatch so the bus voltage settles back to
                    % V_ref_per_bus.  The index then measures a truly healthy
                    % operating point and a later, sustained-healthy dwell
                    % releases the IBR to GFL (dynamic, not a forced handback).
                    obj.restore_healthy_setpoint();
                end
            else
                obj.down_since = NaN;
            end
            if ~isnan(obj.down_since) && (t - obj.down_since) >= obj.T_d_off && ...
                    (t - obj.mode_entry_time) >= obj.T_d_off
                [x_new, info] = obj.transfer_to(x, y, t, 'gfl', info);
                did_switch = true;
            end
        end

        function [x_new, info] = commit_mode(obj, x, y, t, target)
            %COMMIT_MODE  Force a bumpless transfer into TARGET mode ('gfl'|'GFM')
            %   regardless of the index (used for a coordinated reference handback
            %   when the SG slack recloses). Current-continuous like maybe_switch.
            if nargin < 5, error('ibr:SwitchableIbr6:commitMode','target required.'); end
            [x_new, info] = obj.transfer_to(x, y, t, char(target), struct());
        end

        function restore_to_gfl(obj, t)
            %RESTORE_TO_GFL  Reference handback to GFL at a synchronized SG reclose
            %   (counts as one transition; clears the RoCoF memory so no spurious
            %   spike is seen at the restored operating point).
            if ~strcmp(obj.mode,'gfl')
                obj.n_switch = obj.n_switch + 1; obj.last_switch_time = t;
            end
            obj.mode = 'gfl';
            obj.u(1:2) = [obj.P_ref0; obj.Q_ref0];
            obj.mode_entry_time = t; obj.up_since = NaN; obj.down_since = NaN;
            obj.f_prev = NaN; obj.t_prev = NaN; obj.rocof_filt = NaN;
        end

        function handback_scheduled_reference(obj)
            %HANDBACK_SCHEDULED_REFERENCE Restore the pre-event P/Q schedule.
            %   This is deliberately separate from a mode command: after the SG
            %   reference returns, the IBR remains GFM until its local AGSI++ is
            %   below Gamma_off for T_d_off.  Restoring the dispatch at reclose
            %   prevents the island-support setpoint and the returning SG dispatch
            %   from being applied simultaneously (coordinated reference handback).
            obj.u(1:2) = [obj.P_ref0; obj.Q_ref0];
            obj.down_since = NaN;
        end

        function restore_healthy_setpoint(obj)
            %RESTORE_HEALTHY_SETPOINT Return the island-support GFM P/Q setpoint
            %   to the PF-healthy pre-fault dispatch (P_ref0/Q_ref0).  This is the
            %   Q-restore step BEFORE an index-driven GFM->GFL release: once the
            %   SG reference returns, keeping Q at the healthy-dispatch value lets
            %   the bus voltage settle back to V_ref_per_bus, so J_V falls and the
            %   local severity gates the handback (`maybe_switch` releases only
            %   when V/f are healthy again).  Calling this does NOT change mode.
            obj.u(1:2) = [obj.P_ref0; obj.Q_ref0];
        end

        function reset(obj)
            %RESET  Return to the constructed GFL state (for reuse in tests).
            obj.mode = 'gfl';
            obj.switched = false;
            obj.n_switch = 0;
            obj.last_switch_time = NaN;
            obj.mode_entry_time = 0;
            obj.up_since = NaN;
            obj.down_since = NaN;
            obj.f_prev = NaN;
            obj.t_prev = NaN;
            obj.rocof_filt = NaN;
            obj.last_index = 0;
            obj.u(1:2) = [obj.P_ref0; obj.Q_ref0];
        end
    end

    methods (Access = private)
        function [x_new, info] = transfer_to(obj, x, y, t, target, info)
            %TRANSFER_TO  Bumpless (current-continuous) re-initialisation into
            %   TARGET mode at the instantaneous terminal (V,P,Q).
            bp = obj.bus_position;
            V = complex(y(2*bp-1), y(2*bp));
            I_left = obj.current_injection(x, y);
            S = V*conj(I_left);
            P = real(S);
            Q = imag(S);
            switch target
            case 'GFM'
                x_new = obj.gfm_dev.equilibrium_initialize(V, P, Q, struct());
                x_new = x_new(:);
                % Zero-derivative GFM start: P_ref=P and the reactive bias
                % uses the declared terminal-voltage reference E_t.
                % The EECON49 full GFM branch has an explicit E_ref input and
                % needs the source-mapped reactive bias for a zero-derivative
                % transfer.  The legacy reduced GFM branch declares nu=2 and
                % has no E_ref channel; applying that full-model bias there
                % changes its Q command and prevents the diagnostic recovery
                % path from reaching the down-line.  Keep the branch ABI and
                % transfer map paired.
                Eref = obj.u(3);
                if isfield(obj.gfm_dev,'nu') && obj.gfm_dev.nu >= 3
                    p = obj.gfm_dev.provenance.params;
                    Eidx = 5;
                    if isfield(obj.gfm_dev.provenance,'E_index')
                        Eidx = obj.gfm_dev.provenance.E_index;
                    end
                    E0 = x_new(Eidx);
                    Q = Q + p.kE*(E0-Eref)/(p.kQ*p.kappa);
                end
                obj.u = [P; Q; Eref];
                obj.switched = true;
            case 'gfl'
                x_new = obj.gfl_dev.equilibrium_initialize(V, P, Q, struct());
                x_new = x_new(:);
                % GFL equilibrium delivers (P,Q) at V with u=[P;Q].
                obj.u(1:2) = [P; Q];
            otherwise
                error('ibr:SwitchableIbr6:target','Unknown target mode "%s".', target);
            end
            obj.mode = target;
            obj.mode_entry_time = t;
            obj.up_since = NaN;
            obj.down_since = NaN;
            obj.n_switch = obj.n_switch + 1;
            obj.last_switch_time = t;
            I_right = obj.current_injection(x_new, y);
            info.triggered = true;
            info.direction = string(target);
            info.new_mode = string(target);
            info.I_left = I_left;
            info.I_right = I_right;
            info.P = P;
            info.Q = Q;
            info.V = V;
        end

        function u = branch_input(obj, d)
            %BRANCH_INPUT Map the supervisor's fixed input ABI to a branch.
            % The supervisor stores [P_ref; Q_ref; E_ref] so the shared
            % EECON49 GFM branch can consume the explicit E_ref input.  The
            % legacy reduced pair and the EECON49 GFL branch retain their
            % two-input ABI; passing E_ref to those models violates their
            % declared input contract.  Dispatch by the branch's declared
            % dimension rather than a model-name string.
            if ~isstruct(d) || ~isfield(d,'nu') || ~isscalar(d.nu)
                error('ibr:SwitchableIbr6:branchAbi', ...
                    'Active branch lacks a scalar declared input dimension.');
            end
            switch d.nu
                case 2
                    u = obj.u(1:2);
                case 3
                    u = obj.u(1:3);
                otherwise
                    error('ibr:SwitchableIbr6:branchAbi', ...
                        'Unsupported active branch input dimension %g.', d.nu);
            end
        end
    end
end
