classdef EtFcsRateAccumulator
%ETFCSRATEACCUMULATOR  Online active-rate accumulator over ACCEPTED steps.
%   A value object that consumes, one accepted step at a time, the ACTIVE
%   frequency of each online device (from et_fcs_device_frequency) and produces
%   causal per-device f / RoCoF / RoCoV with the protections the plan requires:
%
%   TRANSACTIONAL.  step(...,accepted=false) returns the SAME object unchanged:
%   a rejected (rolled-back) trial consumes NO history and NO timers.  Marking a
%   sample invalid is not enough -- the persistent state itself must not move.
%
%   EPOCH-RESET ON MODE/ONLINE CHANGE.  Each device is a COLUMN keyed by
%   device_index.  When a column's (mode, online) changes -- a GFL<->GFM
%   transfer, a trip, a reclose -- the column's history is CLEARED and its epoch
%   is bumped.  A frozen pre-transfer rate can never be differenced against a
%   post-transfer sample.
%
%   CAUSAL ACTIVE RATES.  RoCoF is the device's OWN active RHS speed derivative
%   when the device exposes a speed state (SG/GFM, via et_fcs_device_frequency
%   fdot_hz_s); a GFL has no speed state, so its RoCoF is the clearly-defined
%   causal backward difference of the PLL frequency.  RoCoV is a causal backward
%   difference of |V| passed through an EMA, so a single step discontinuity does
%   NOT fire a spurious voltage-rate release.
%
%   DUPLICATE EVENT / LEFT-RIGHT JUMP.  Two accepted samples at the same instant
%   (or a non-advancing rollback echo) create NO rate; their |V| left/right
%   values are recorded as a separate jump diagnostic.
%
%   WARMUP.  A column is VALID only once t - started_t >= opt.warmup_s, with a
%   usable stencil and finite inputs.
%
%   See also et_fcs_device_frequency, et_fcs_rate_gates, et_fcs_causal_rates.

    properties (SetAccess = immutable)
        opt            % resolved options
    end

    properties (SetAccess = private)
        col            % 1xN struct array of per-device columns
    end

    methods
        function obj = EtFcsRateAccumulator(opt)
            arguments
                opt struct = struct()
            end
            o = struct();
            o.fbase     = optval(opt,'fbase',60.0);
            o.warmup_s  = optval(opt,'warmup_s',0.02);
            o.min_dt    = optval(opt,'min_dt',1e-9);
            o.dup_tol   = optval(opt,'dup_tol',1e-12);
            o.rocov_alpha = optval(opt,'rocov_alpha',0.2);
            o.rocov_tau_s = optval(opt,'rocov_tau_s',NaN);
            if ~isnan(o.rocov_tau_s) && (~isfinite(o.rocov_tau_s) || o.rocov_tau_s<=0)
                error('stability:EtFcsRateAccumulator:badTau','rocov_tau_s ต้องเป็นบวก');
            end
            if o.rocov_alpha<=0 || o.rocov_alpha>1
                error('stability:EtFcsRateAccumulator:badAlpha', ...
                    'rocov_alpha must be in (0,1].');
            end
            obj.opt = o;
            obj.col = empty_columns();
        end

        function [obj, staged] = step(obj, t, sample, accepted)
        %STEP  Consume one step's active-frequency sample set.
        %   SAMPLE is a struct array with fields:
        %     device_index, mode, online, f_hz, v_mag, fdot_hz_s (optional)
        %   ACCEPTED=false returns OBJ unchanged (no history/timers consumed).
            arguments
                obj
                t (1,1) double {mustBeFinite}
                sample struct
                accepted (1,1) logical
            end
            staged = empty_staged();
            if isempty(sample)
                return;
            end
            if ~accepted
                return;                       % rolled back: state untouched
            end
            for s = 1:numel(sample)
                [obj, rec] = obj.advance_column(t, sample(s));
                staged(s) = rec; %#ok<AGROW>
            end
        end

        function r = rates(obj)
        %RATES  Committed causal series as matrices (NaN-padded).
            ncol = numel(obj.col);
            n = 0;
            for k = 1:ncol, n = max(n, numel(obj.col(k).t)); end
            r = struct();
            r.t = nan(n,ncol); r.f_hz = nan(n,ncol);
            r.rocof_hz_s = nan(n,ncol); r.rocov_pu_s = nan(n,ncol);
            r.rocov_pu_raw_s = nan(n,ncol);
            r.valid = false(n,ncol);
            r.device_index = nan(1,ncol); r.mode = cell(1,ncol);
            r.source = cell(1,ncol); r.epoch = zeros(1,ncol);
            for k = 1:ncol
                c = obj.col(k); m = numel(c.t);
                if m>0
                    r.t(1:m,k)=c.t; r.f_hz(1:m,k)=c.f;
                    r.rocof_hz_s(1:m,k)=c.rocof; r.rocov_pu_s(1:m,k)=c.rocov;
                    r.rocov_pu_raw_s(1:m,k)=c.rocov_raw;
                    r.valid(1:m,k)=c.valid;
                end
                r.device_index(k)=c.key; r.mode{k}=c.mode;
                r.source{k}=c.source; r.epoch(k)=c.epoch;
            end
            r.n_columns = ncol;
            r.fbase = obj.opt.fbase;
            r.method = 'active_omega_causal_accepted_steps';
            r.classification = 'PROJECT_DERIVED';
        end

        function g = gates(obj, gate_struct, dwell_s)
        %GATES  Independent SI/ROCOF/ROCOV gates + release dwell per column.
            arguments
                obj
                gate_struct struct
                dwell_s (1,1) double = 0.20
            end
            r = obj.rates();
            g = struct('device_index',{},'gate',{},'dwell',{});
            for k = 1:r.n_columns
                rr = struct('f_hz',r.f_hz(:,k),'rocof_hz_s',r.rocof_hz_s(:,k), ...
                    'rocov_pu_s',r.rocov_pu_s(:,k),'valid',r.valid(:,k), ...
                    't',r.t(:,k));
                [gt, dw] = stability.et_fcs_rate_gates(rr, gate_struct, ...
                    struct('t',r.t(:,k),'dwell_s',dwell_s));
                g(k).device_index = r.device_index(k);
                g(k).gate = gt; g(k).dwell = dw;
            end
        end

        function j = jump_diagnostics(obj)
        %JUMP_DIAGNOSTICS  Left/right |V| jump recorded at duplicate instants.
            ncol = numel(obj.col);
            j = struct('device_index',nan(1,ncol),'v_left',nan(1,ncol), ...
                'v_right',nan(1,ncol),'jump',nan(1,ncol),'count',zeros(1,ncol));
            for k = 1:ncol
                j.device_index(k)=obj.col(k).key;
                j.v_left(k)=obj.col(k).jump_left;
                j.v_right(k)=obj.col(k).jump_right;
                j.jump(k)=obj.col(k).jump_right-obj.col(k).jump_left;
                j.count(k)=obj.col(k).jump_count;
            end
        end
    end

    methods (Access = private)
        function [obj, rec] = advance_column(obj, t, s)
            rec = struct('device_index',s.device_index,'f_hz',NaN, ...
                'rocof_hz_s',NaN,'rocov_pu_s',NaN,'valid',false,'epoch',0,'note','');
            ci = find([obj.col.key]==s.device_index, 1);
            online = logical(s.online);
            mode = char(string(s.mode));
            if isempty(ci)
                c = new_column(s.device_index, t, mode, online, s.f_hz, s.v_mag);
                obj.col(end+1) = c;
                rec.epoch = c.epoch; rec.note = 'column_created';
                return;
            end
            c = obj.col(ci);
            % --- epoch reset on mode/online change ---
            if ~strcmp(c.mode,mode) || c.online ~= online
                c = new_column(s.device_index, t, mode, online, s.f_hz, s.v_mag);
                c.epoch = obj.col(ci).epoch + 1;      % monotone, informative
                obj.col(ci) = c;
                rec.epoch = c.epoch; rec.note = 'epoch_reset';
                return;
            end
            if ~online || strcmpi(mode,'tripped')
                % offline while same epoch can't happen (online is part of the
                % epoch key); defensive: emit invalid without consuming history.
                rec.epoch = c.epoch; rec.note = 'offline';
                return;
            end
            % --- non-advancing instant: duplicate event / rejected echo ---
            dt = t - c.last_t;
            if ~isfinite(dt) || dt <= obj.opt.dup_tol
                c.jump_left = c.last_v; c.jump_right = s.v_mag;
                c.jump_count = c.jump_count + 1;      % time NOT advanced
                % right-limit เป็นฐาน stencil ถัดไป; jump ไม่ปน continuous ROCOV.
                if abs(dt)<=obj.opt.dup_tol
                    c.last_v = s.v_mag; c.last_f = s.f_hz;
                end
                obj.col(ci) = c;
                rec.epoch = c.epoch; rec.note = 'duplicate_instant';
                return;
            end
            if dt < obj.opt.min_dt
                rec.epoch = c.epoch; rec.note = 'sub_min_dt';
                return;
            end
            % --- causal active rates ---
            f_hz = s.f_hz;
            rocof_raw = (f_hz - c.last_f)/dt;
            rocov_raw = (s.v_mag - c.last_v)/dt;
            % Prefer the device's active RHS speed derivative for RoCoF when the
            % device exposes one (SG/GFM).  GFL has no speed state: causal diff.
            if isfield(s,'fdot_hz_s') && isscalar(s.fdot_hz_s) && isfinite(s.fdot_hz_s)
                rocof = s.fdot_hz_s; rec.note = 'rocof_active_rhs';
            else
                rocof = rocof_raw; rec.note = 'rocof_causal_diff';
            end
            a = obj.opt.rocov_alpha;
            if isfinite(obj.opt.rocov_tau_s)
                a = -expm1(-dt/obj.opt.rocov_tau_s); % time constant บน dt จริง
            end
            if isfinite(c.rocov_s)
                rocov_s = a*rocov_raw + (1-a)*c.rocov_s;
            else
                rocov_s = rocov_raw;
            end
            warm = (t - c.started_t) >= obj.opt.warmup_s;
            valid = warm && isfinite(f_hz) && isfinite(rocof) && isfinite(rocov_s);
            c.t(end+1)=t; c.f(end+1)=f_hz; c.rocof(end+1)=rocof;
            c.rocov(end+1)=rocov_s; c.rocov_raw(end+1)=rocov_raw;
            c.valid(end+1)=valid;
            c.last_t=t; c.last_f=f_hz; c.last_v=s.v_mag; c.rocov_s=rocov_s;
            obj.col(ci)=c;
            rec.f_hz=f_hz; rec.rocof_hz_s=rocof; rec.rocov_pu_s=rocov_s;
            rec.valid=valid; rec.epoch=c.epoch;
        end
    end
end

% -------------------------------------------------------------------------
function o = optval(opt, name, default)
if isfield(opt,name) && ~isempty(opt.(name)), o=double(opt.(name)); else, o=default; end
end

function c = empty_columns()
c = struct('key',{},'mode',{},'online',{},'epoch',{},'t',{},'f',{}, ...
    'rocof',{},'rocov',{},'rocov_raw',{},'valid',{},'started_t',{},'last_t',{},'last_f',{}, ...
    'last_v',{},'rocov_s',{},'source',{},'jump_left',{},'jump_right',{}, ...
    'jump_count',{});
end

function c = new_column(key, t, mode, online, f_hz, v_mag)
c = struct('key',key,'mode',mode,'online',online,'epoch',1, ...
    't',zeros(1,0),'f',zeros(1,0),'rocof',zeros(1,0),'rocov',zeros(1,0), ...
    'rocov_raw',zeros(1,0), ...
    'valid',false(1,0),'started_t',t,'last_t',t,'last_f',f_hz, ...
    'last_v',v_mag,'rocov_s',NaN,'source','','jump_left',NaN,'jump_right',NaN, ...
    'jump_count',0);
end

function s = empty_staged()
s = struct('device_index',{},'f_hz',{},'rocof_hz_s',{},'rocov_pu_s',{}, ...
    'valid',{},'epoch',{},'note',{});
end
