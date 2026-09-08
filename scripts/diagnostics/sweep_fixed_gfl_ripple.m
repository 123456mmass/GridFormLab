function out = sweep_fixed_gfl_ripple(varargin)
%SWEEP_FIXED_GFL_RIPPLE  Find a PLL setting at which the all-GFL island really
% oscillates, instead of settling to a constant.
%
% THE PROBLEM THIS SOLVES. The Fixed-GFL comparison arm is supposed to show what
% the policy this project rejects actually does: an energised island with no
% voltage-forming source. The delivered diagnostic arm reaches 250 s but SETTLES
% -- measured on the cached run, |V| at bus 9 sits at 0.663247 pu and moves by
% 1e-6 per sample over 100-105 s. There is nothing to see. Drawing a "wobble" on
% top of that would be decoration, not a result, so the alternative is to find a
% parameter set in which the island genuinely rings, and declare it.
%
% THE MECHANISM, not a guess. With every converter grid-following and the machine
% gone, each device's angle comes from its own PLL locked to a bus voltage that is
% produced entirely by the currents those same PLLs command. The loop is a
% PLL-network interaction whose small-signal pair is, per converter,
%
%     s^2 + k_pPLL |V| s + k_iPLL |V| = 0
%     omega_n = sqrt(k_iPLL |V|),   zeta = k_pPLL sqrt(|V|) / (2 sqrt(k_iPLL))
%
% so k_iPLL sets the ring frequency and k_pPLL sets its damping. The delivered
% pair (1.2, 5.0) at |V| = 0.70 gives omega_n = 1.87 rad/s (0.30 Hz) and
% zeta = 0.27 -- decayed within a few seconds, which is exactly what the cache
% shows. Lowering k_pPLL at fixed k_iPLL walks that pair toward the imaginary
% axis; raising k_iPLL moves the ring into the 1-2 Hz band where it is visible
% across a 160 s axis.
%
% WHAT IS AND IS NOT CHANGED. The override is applied to
% scenario.resources(k).dynamic_params.gfl_eecon49 AFTER the case is built, so
% +cases/scenario_ieee14_1sg_4ibr.m and every production path are untouched. The
% GFL equations, the limiter, the anti-windup, the DC closure, the solver and
% every acceptance gate are the delivered ones. Only two controller gains move,
% and only on this diagnostic arm.
%
% The stepper is FIXED here, not adaptive. The adaptive controller stretches dt
% to 0.5 s on a quiet island, which would alias a 1 Hz ring into nonsense: the
% ripple has to be resolved to be measured.
%
% Classification: ASSUMED_DIAGNOSTIC probe. Writes one summary file and no
% trajectory; nothing here feeds a production path.

pf_init_paths();

ip = inputParser;
ip.addParameter('TEnd',50);        % sg_trip at 20, so 30 s of island
ip.addParameter('Dt',0.02);        % 50 Hz sampling: resolves a 2 Hz ring
ip.addParameter('Grid',[]);        % rows of [kpPLL kiPLL]
ip.parse(varargin{:});

grid_pll = ip.Results.Grid;
if isempty(grid_pll)
    grid_pll = [ ...
        1.20   5.00; ...   % delivered pair, the control
        0.36  56.00; ...   % zeta ~ 0.02 at 1.0 Hz by the formula above
        0.20  56.00; ...   % same frequency, a third of the damping
        0.10  56.00; ...   % near-zero damping
        0.20 220.00; ...   % ~2.0 Hz
        0.10 220.00];
end

out = struct('kpPLL',{},'kiPLL',{},'converged',{},'t_end',{},'n',{}, ...
    'V9_min',{},'V9_max',{},'V9_ptp',{},'V9_std',{},'f_ring_Hz',{}, ...
    'n_crossings',{},'failure_id',{});

for k = 1:size(grid_pll,1)
    kp = grid_pll(k,1);
    ki = grid_pll(k,2);
    fprintf('--- kpPLL=%.3f kiPLL=%.2f ---\n',kp,ki);
    try
        r = one_run(kp,ki,ip.Results.TEnd,ip.Results.Dt);
    catch err
        fprintf('    ERROR %s\n',err.identifier);
        out(end+1) = blank_row(kp,ki,err.identifier); %#ok<AGROW>
        continue;
    end
    % run_hybrid_case returns a STRUCTURED failure rather than throwing
    % (run_hybrid_case.m:82,127,335,465), and such a result carries no
    % trajectory fields at all. Reading bus_ids off it would raise an
    % unrecognised-field error and lose the reason the run actually failed.
    if ~isfield(r,'bus_ids') || ~isfield(r,'t') || isempty(r.t)
        fid = '';
        if isfield(r,'failure_id') && ~isempty(r.failure_id)
            fid = char(string(r.failure_id));
        elseif isfield(r,'metadata') && isstruct(r.metadata) && ...
                isfield(r.metadata,'failure')
            fid = char(string(r.metadata.failure));
        end
        why = '';
        if isfield(r,'metadata') && isstruct(r.metadata) && ...
                isfield(r.metadata,'error')
            why = char(string(r.metadata.error));
        end
        fprintf('    NO TRAJECTORY  failure=%s  %s\n',fid,why);
        out(end+1) = blank_row(kp,ki,fid); %#ok<AGROW>
        continue;
    end
    m = measure(r,22,ip.Results.TEnd);

    m.kpPLL = kp; m.kiPLL = ki;
    m.converged = logical(r.converged);
    m.t_end = r.t(end);
    m.failure_id = char(string(r.failure_id));
    out(end+1) = orderfields(m,blank_row(kp,ki,'')); %#ok<AGROW>

    fprintf(['    conv=%d  t_end=%.2f  n=%d  V9 %.4f..%.4f  ptp %.4f  ' ...
             'std %.4f  ring %.3f Hz  crossings %d\n'], ...
        m.converged,m.t_end,m.n,m.V9_min,m.V9_max,m.V9_ptp,m.V9_std, ...
        m.f_ring_Hz,m.n_crossings);
end

odir = fullfile('output','diagnostics','ieee14_locked_gfl_diag');
if ~isfolder(odir), mkdir(odir); end
save(fullfile(odir,'ripple_sweep.mat'),'out');
fprintf('wrote %s\n',fullfile(odir,'ripple_sweep.mat'));
end

% ==========================================================================
function m = blank_row(kp,ki,fid)
%BLANK_ROW  One result row for a run that produced no trajectory.
%   Field ORDER here is the canonical order every row is written in, so the
%   struct array concatenates.
m = struct('kpPLL',kp,'kiPLL',ki,'converged',false,'t_end',NaN,'n',0, ...
    'V9_min',NaN,'V9_max',NaN,'V9_ptp',NaN,'V9_std',NaN, ...
    'f_ring_Hz',NaN,'n_crossings',NaN,'failure_id',fid);
end

% ==========================================================================
function r = one_run(kpPLL,kiPLL,t_end,dt)

sys = ibr.build_ieee14_switch_system(index_mode='agsi_pp', ...
    case_profile='eecon49_figure4',sg_H=2.5,sg_D=1.0, ...
    T_d_on=0.10,T_d_off=1.0);
scenario = cases.scenario_ieee14_1sg_4ibr( ...
    struct('case_profile','eecon49_figure4'));

% The diagnostic gain override, applied to the resource table only.
for k = 1:numel(scenario.resources)
    rk = scenario.resources(k);
    if ~strcmpi(char(rk.resource_type),'ibr'), continue; end
    if ~isfield(rk,'dynamic_params') || ...
            ~isfield(rk.dynamic_params,'gfl_eecon49')
        error('sweep_fixed_gfl_ripple:noGflParams', ...
            'Resource %s carries no dynamic_params.gfl_eecon49.', ...
            char(rk.resource_id));
    end
    scenario.resources(k).dynamic_params.gfl_eecon49.kpPLL = kpPLL;
    scenario.resources(k).dynamic_params.gfl_eecon49.kiPLL = kiPLL;
end

selector_table = stability.ibr_selector_table(scenario.case_data, ...
    scenario.resources,scenario,struct());

% The island window is what the probe measures, so the reclose is pushed to the
% last instant the ordering contract allows rather than removed: 'sg_cycle' arms
% sg_trip AND sg_reclose and requires sg_trip < sg_on <= t_end, so there is no
% way to ask for a trip without an offer. sg_on = t_end - 0.1 leaves the whole
% 20..t_end-0.1 window islanded, which is the window measure() reads.
events = struct('enabled',true,'event_profile','sg_cycle', ...
    'sg_trip',20,'sg_on',t_end-0.1, ...
    'coordinated_handback',false, ...
    'delays_overrides',struct('timeout_s',20,'dwell_s',0.5), ...
    'automatic_gfm_switching',false);


opt = struct( ...
    't_end',t_end,'dt',dt,'verbose',false,'plot_results',false, ...
    'max_step_subdivisions',12,'state_predictor','linear_kcl', ...
    'automatic_support_supervision',true, ...
    'severity_gamma_on',0.65,'severity_gamma_off',0.35, ...
    'severity_T_d_on',0.10,'severity_T_d_off',1.00, ...
    'healthy_pf_V',sys.pf.bus_voltage(:).', ...
    'healthy_pf_bus_ids',sys.pf.external_bus_ids(:).', ...
    'stepper','fixed','reject_limit',20, ...
    'support_transition_certificate',true, ...
    'handback_efd_timescale','control', ...
    'anti_windup_blend',1e-3, ...
    'allow_no_vf_island',true, ...
    'angle_gauge_bus',1,'angle_gauge_after',events.sg_trip+0.25, ...
    'selector_table',selector_table, ...
    'ibr_events',events);

scenario.scenario_opt.ibr_factory_override = struct();
for rid = ["IBR2","IBR3","IBR6","IBR8"]
    scenario.scenario_opt.ibr_factory_override.(char(rid)) = ...
        @ibr.eecon49_dual_mode_ideal_dc;
end

r = stability.run_hybrid_case(scenario,opt);
end

% ==========================================================================
function m = measure(r,t0,t1)
%MEASURE  Ripple statistics of |V| at bus 9 over the island window.
t = r.t(:);
b9 = find(r.bus_ids(:).'==9,1);
V9 = r.bus_voltage_magnitude(b9,1:numel(t)).';
w = t>=t0 & t<=t1;
v = V9(w);
tt = t(w);
m = struct();
m.n = numel(v);
if m.n < 8
    m.V9_min=NaN; m.V9_max=NaN; m.V9_ptp=NaN; m.V9_std=NaN;
    m.f_ring_Hz=NaN; m.n_crossings=NaN; return;
end
m.V9_min = min(v); m.V9_max = max(v);
m.V9_ptp = m.V9_max - m.V9_min;
m.V9_std = std(v);
% Ring frequency from the dominant spectral line of the mean-removed signal, and
% a crossing count as an independent read on the same thing.
d = v - mean(v);
n = numel(d);
dtm = median(diff(tt));
F = abs(fft(d.*hann_local(n)));
F = F(1:floor(n/2));
fr = (0:numel(F)-1).'/(n*dtm);
[~,i] = max(F(2:end));
m.f_ring_Hz = fr(i+1);
m.n_crossings = sum(diff(sign(d))~=0);
end

function w = hann_local(n)
w = 0.5*(1-cos(2*pi*(0:n-1).'/(n-1)));
end
