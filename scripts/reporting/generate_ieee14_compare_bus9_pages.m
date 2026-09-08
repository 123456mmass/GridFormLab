function out = generate_ieee14_compare_bus9_pages(opts)
%GENERATE_IEEE14_COMPARE_BUS9_PAGES  Adaptive against fixed-GFL at bus 9, two pages.
%
%   out = generate_ieee14_compare_bus9_pages()
%
% The owner's 2x2 bus-9 comparison -- the figure
% generate_bus9_adaptive_vs_fixed_160s.m delivers to the report -- SPLIT INTO TWO
% SLIDE PAGES of two panels each, laid out and lettered exactly like the deck's V/f
% and P/Q pages (2026-09-05: "the same as this, but split two graphs per page as
% before"):
%
%   <id>_cmp_pq.png   (a) P_Bus9    (b) Q_Bus9
%   <id>_cmp_vf.png   (a) |V_Bus9|  (b) f_Bus9
%
%   blue = the delivered adaptive GFL/GFM switching policy (PROJECT_RESULT)
%   grey = the same case with every converter locked grid-following
%          (ASSUMED_DIAGNOSTIC: a comparison-only continuation, never a readiness
%          claim -- it runs with the opt-in allow_no_vf_island suspension and the
%          angle_gauge_bus=1 slack pin, and the production noVoltageFormingSource
%          refusal is untouched)
%
% Bus 9 is the fault bus and carries load but no device, so it reports what the
% island DELIVERS to a load bus rather than what any one controller commands.
%
% NO MODE STRIP on these pages, unlike their two siblings. The strip's lanes are
% per-converter in the IBR palette, whose first hue IS this page's blue -- and here
% blue means a POLICY, not IBR_1. A blue bar above a blue trace would read as the
% adaptive arm's own bar rather than as a converter's, so the strip is left to the
% pages where colour means a converter.
%
% NO VERTICAL EVENT RULES and the panel tag BELOW the x label, centred: the same
% styling the owner set on the V/f and P/Q pages. Every scheduled instant is listed
% in the provenance file instead.
%
% PANEL (b) OF THE V/f PAGE IS THE FREQUENCY AT BUS 9 ITSELF, at the owner's
% instruction (2026-09-05: "the f graph is f at bus 9"). Bus 9 carries load but no
% device, so no frequency is a state there and none is published for it; it is DERIVED
% from the bus's own voltage angle, which IS a solved algebraic variable of the run:
%
%     f_9(t) = f_0 + (1/2pi) * d(theta_9)/dt
%
% taken as the secant slope of the unwrapped angle across each accepted step -- the
% average frequency over that step, carried at the step's midpoint. Both arms are
% derived the same way from their own solutions, which is what makes the two policies
% comparable on this panel at all; the earlier draft drew the PUBLISHED converter
% frequency instead, and the grey arm had nothing to show there because a
% grid-following row publishes no absolute frequency.
%
% FOUR THINGS THAT WOULD MAKE THAT DERIVATION WRONG, all handled and all gated:
%   1. THE FRAME. An angle rate is a frequency only if the frame it is measured in
%      rotates at f_0. Gated by measurement: before the first event both arms are
%      synchronous, so theta_9 must be STATIONARY -- measured |d theta_9| = 0.000e+00
%      rad over every pre-trip step of both arms (42 and 1000 of them), giving
%      f_9 = 60.000000000 Hz exactly. A frame that drifted would show up here.
%   2. WRAPPING. theta_9 is returned on (-pi, pi]; the angle is unwrapped before it is
%      differenced. On the fixed arm the raw difference exceeds pi/2 on 4318 steps, so
%      differencing the wrapped angle would manufacture jumps that are not motion.
%   3. THE EVENT JUMP. A switching transaction moves the algebraic state
%      discontinuously and publishes a left and a right sample AT ONE INSTANT (dt = 0:
%      8 such pairs on the adaptive arm, 4 on the fixed). A difference across that pair
%      is not a rate at all, so zero-length steps are dropped rather than divided by.
%   4. RESOLUTION. A secant can only express |f - f_0| <= 1/(2 dt); beyond a half turn
%      per step the true motion is theta + 2 pi k for unknown k and the number is the
%      GRID's bound, not the run's. Steps whose |d theta| reaches pi/2 -- half that
%      limit -- are therefore NOT DRAWN, and how many were dropped is reported. This
%      matters entirely on the fixed arm, whose 20 ms output grid leaves 3514 of its
%      8002 steps (70.3 s of 160) undetermined: its bus-9 angle swings up to pi radians
%      per step. The adaptive arm's own grid resolves every one of its 2279 steps.
%
% So the grey trace on that panel is BROKEN, not absent: it is drawn where its own
% output grid determines the rate and gapped where it does not, and the gaps are
% themselves the finding -- a fixed-GFL fleet at this bus moves its angle faster than
% the run recorded it. Measured on the determined, off-event samples: the adaptive arm
% holds bus 9 within [59.27, 63.62] Hz, the fixed arm reaches [47.53, 72.50] Hz.
%
% CONTRACT
%   - Pure cache reader: no simulation, no write-back. The two arms carry DIFFERENT
%     accepted-sample grids (2288 adaptive against 8007 fixed); each is drawn on its
%     own t and never resampled onto the other's.
%   - The trajectories are NEVER modified: no smoothing, filtering, decimation,
%     interpolation, offset or resampling, and no synthetic augmentation layer.
%   - LINE-ONLY: no area, fill or patch under any curve. A thin trace must never read
%     as a thick one, which is the confusion an oscillation comparison must not make.
%   - Y windows cover BOTH arms over the operating band, so the two policies share
%     one scale per panel; anything outside is annotated AT THE FRAME with its peak.
%   - Fail-closed: every assert aborts before any file is written.
%
% Classification: presentation only. No value computed here feeds PF, SSSA, TS, a
% selector, a controller or an acceptance decision.
%
% Regenerate with:
%   pf_init_paths; generate_ieee14_compare_bus9_pages()
arguments
    opts.adaptive_cache (1,1) string = ...
        fullfile('output','diagnostics','ieee14_scenario_suite', ...
                 'sg_fault_cycle160.mat')
    opts.fixed_cache (1,1) string = ...
        fullfile('output','diagnostics','ieee14_locked_gfl_diag', ...
                 'locked_gfl_diag_160s.mat')
    opts.out_dir (1,1) string = fullfile('docs','source','figures', ...
        'ieee14_scenario_suite')
    opts.id (1,1) string = "sg_fault_cycle160"
    % The V/f and P/Q deck pages' canvas exactly, so all four pages of this arm
    % occupy one rectangle on a slide at 1:1 and their 10 pt lettering arrives at
    % 10 pt. Height 2.62 rather than 2.90: these pages carry no mode strip, so the
    % 0.35 in the strip and its caption take is returned to the data panels.
    opts.width_in (1,1) double {mustBePositive} = 4.65
    opts.height_in (1,1) double {mustBePositive} = 2.62
    opts.font_size (1,1) double {mustBePositive} = 10
    opts.font_name (1,1) string = "Helvetica"
    opts.dpi (1,1) double {mustBePositive} = 300
    opts.save_fig (1,1) logical = true
    % Fault window excluded from the Y WINDOW, never from the data: the bolted fault
    % drives every channel far outside its operating band, so a window containing it
    % compresses the whole islanded comparison. Anything leaving the window is
    % annotated at the frame with its peak value.
    opts.fault_window (1,2) double = [60 60.20]
    % The bus-9 frequency channel, whose derivation the header documents.
    %
    % DETERMINED_RAD is the resolution gate: a secant over one accepted step can only
    % express an angle motion below pi, so a step whose |d theta| reaches this bound is
    % not drawn. pi/2 is half the wrap limit, i.e. a factor-of-two margin -- measured
    % consequence: 0 of the adaptive arm's 2279 steps are dropped, 3514 of the fixed
    % arm's 8002 are.
    opts.determined_rad (1,1) double {mustBePositive} = pi/2
    % EVENT_PAD keeps the frequency panel's WINDOW off the switching instants. The
    % first short step after a transaction carries a genuine but very large rate (up to
    % 136.7 Hz on the adaptive arm at the fault clear), which would set an axis that
    % flattens the whole comparison. The samples are still DRAWN and the excursion is
    % annotated at the frame; only the window ignores them.
    opts.event_pad (1,1) double {mustBeNonnegative} = 0.25
end

pf_init_paths();
afile = char(opts.adaptive_cache);
xfile = char(opts.fixed_cache);
odir = char(opts.out_dir);
if ~isfolder(odir), mkdir(odir); end
id = char(opts.id);

[Ra,Rx,sha_a,sha_x,fixed_pll,t_events,S9_pf,V9_pf,y9] = ...
    read_both(afile,xfile);
% The schedule is READ from the arms rather than declared as an option: the frequency
% panel's window is set off these instants, so a hard-coded list that drifted from the
% run would exclude the wrong stretch.
opts.event_times = t_events;

B = struct();
B.adaptive = bus9_signals(Ra,y9,opts.determined_rad);
B.fixed = bus9_signals(Rx,y9,opts.determined_rad);
identity_gate(B,S9_pf,V9_pf,afile,xfile);
frequency_frame_gate(B,afile,xfile);

out = struct();
out.schema = 'ieee14_compare_bus9_pages/1.0';
out.classification = 'PRESENTATION_ONLY';
out.generated_utc = char(datetime('now','TimeZone','UTC', ...
    'Format','yyyy-MM-dd''T''HH:mm:ssXXX'));
out.style = struct('width_in',opts.width_in,'height_in',opts.height_in, ...
    'font_size',opts.font_size,'font_name',char(opts.font_name), ...
    'interpreter','tex','box','off','tick_dir','out', ...
    'grid','dashed major and minor');
out.adaptive_cache = afile;
out.fixed_cache = xfile;
out.adaptive_sha = sha_a;
out.fixed_sha = sha_x;
out.fixed_pll_gains = fixed_pll;
out.t_events = t_events;
out.n_samples = [numel(Ra.t) numel(Rx.t)];
out.bus9_reference = struct('S9_pf',S9_pf,'V9_pf',V9_pf,'y9',y9);
out.fault_window = opts.fault_window;
out.frequency = struct( ...
    'definition','f_9 = f0 + (1/2pi) d(theta_9)/dt, secant per accepted step', ...
    'determined_rad',opts.determined_rad, ...
    'event_pad_s',opts.event_pad, ...
    'adaptive',B.adaptive.f_diag,'fixed',B.fixed.f_diag);

out.pages = draw_pages(B,opts,odir,id);
out.measured = measured_table(B,opts);
write_provenance(odir,out);

for k = 1:numel(out.pages)
    p = out.pages(k);
    fprintf('[%s] %s: %d panel(s) | %s\n',id,p.sheet,numel(p.panels), ...
        strjoin(arrayfun(@(q)sprintf('%s %s',q.channel,mat2str(q.window,5)), ...
        p.panels,'UniformOutput',false),' | '));
end
end

% ==========================================================================
function [Ra,Rx,sha_a,sha_x,fixed_pll,t_events,S9_pf,V9_pf,y9] = ...
    read_both(afile,xfile)
%READ_BOTH  Load both arms and every gate that must hold before anything is drawn.
%   Every check here is generate_bus9_adaptive_vs_fixed_160s's, kept verbatim in
%   substance: the two pages this file writes make the same claim as that figure, so
%   they must not be drawable on inputs that figure would refuse.
[Sa,sha_a] = load_guarded(afile);
[Sx,sha_x] = load_guarded(xfile);

% The adaptive suite cache nests its classification inside the stored arm (result
% carries the trajectory; arm carries the runner's record), while the fixed-arm cache
% carries its own top-level field. Read each from where its writer put it.
acl = '';
if isfield(Sa,'arm') && isstruct(Sa.arm) && isfield(Sa.arm,'classification')
    acl = char(string(Sa.arm.classification));
end
assert(strcmp(acl,'PROJECT_RESULT'), ...
    'generate_ieee14_compare_bus9_pages:adaptiveClassification', ...
    'Adaptive cache arm classification is "%s", expected PROJECT_RESULT.',acl);
assert(isfield(Sx,'classification') && ...
    strcmp(char(string(Sx.classification)),'ASSUMED_DIAGNOSTIC'), ...
    'generate_ieee14_compare_bus9_pages:fixedClassification', ...
    ['Fixed-GFL cache classification is "%s"; these pages may only draw an ' ...
     'ASSUMED_DIAGNOSTIC continuation as the grey arm.'], ...
    char(string(field_or(Sx,'classification','<missing>'))));
Ra = Sa.result;
Rx = Sx.result;
assert(logical(Ra.converged) && abs(Ra.t(end)-160) < 5e-4, ...
    'generate_ieee14_compare_bus9_pages:adaptiveOutcome', ...
    'Adaptive arm ends at %.6f s (converged %d), expected 160 s.', ...
    Ra.t(end),logical(Ra.converged));
assert(logical(Rx.converged) && abs(Rx.t(end)-160) < 5e-4, ...
    'generate_ieee14_compare_bus9_pages:fixedOutcome', ...
    'Fixed-GFL arm ends at %.6f s (converged %d), expected 160 s.', ...
    Rx.t(end),logical(Rx.converged));
assert(strcmp(sha_a,sha256_of(afile)) && strcmp(sha_x,sha256_of(xfile)), ...
    'generate_ieee14_compare_bus9_pages:inputChangedWhileReading', ...
    'A generated input changed during this run; a concurrent writer is active.');

fixed_pll = [NaN NaN];
if isfield(Sx,'pll_gains') && numel(Sx.pll_gains) >= 2
    fixed_pll = double(Sx.pll_gains(1:2));
end

% --- one schedule on both arms -------------------------------------------
t_events = schedule_times(Ra);
assert(isequal(t_events,schedule_times(Rx)), ...
    'generate_ieee14_compare_bus9_pages:scheduleDisagreement', ...
    'The adaptive and fixed arms do not share one event schedule.');
assert(max(abs(t_events-[20 60 60.15 100])) < 1e-10, ...
    'generate_ieee14_compare_bus9_pages:scheduleMismatch', ...
    'Event schedule differs from the sg_fault_cycle160 [20 60 60.15 100] s.');
for nm = {'Ra','Rx'}
    r = eval(nm{1});
    assert(isequal(r.device_bus_ids(:)',[1 2 3 6 8]), ...
        'generate_ieee14_compare_bus9_pages:deviceMappingMismatch', ...
        'Arm %s does not map resources 1..5 to buses [1 2 3 6 8].',nm{1});
end
assert(isequal(Ra.sched.Zf,Rx.sched.Zf), ...
    'generate_ieee14_compare_bus9_pages:faultImpedance', ...
    'The two arms disagree on the fault impedance.');

% No load step on this schedule: the runner's sg_fault_cycle160 row clears every load
% field, so neither arm may carry one. A present-but-zero factor is the same
% statement; a nonzero one would put a live multiplier on S_9 and the identity gate
% below would be checking the wrong value.
for nm = {'Ra','Rx'}
    r = eval(nm{1});
    lf = [];
    if isfield(r.sched,'load_step_factor') && ~isempty(r.sched.load_step_factor)
        lf = double(r.sched.load_step_factor);
        lf = lf(isfinite(lf));
    end
    assert(isempty(lf) || all(lf == 0), ...
        'generate_ieee14_compare_bus9_pages:unexpectedLoadStep', ...
        'Arm %s carries a nonzero load-step factor; this schedule has none.',nm{1});
end

% --- bus-9 shunt admittance, from the CASE, not the trajectory -----------
case_data = cases.case_ieee14bus_eecon49_switch();
mpc = case_data.mpc;
sys = ibr.build_ieee14_switch_system(index_mode='agsi_pp', ...
    case_profile='eecon49_figure4',sg_H=2.5,sg_D=1.0,T_d_on=0.10,T_d_off=1.0);
bus9 = find(Ra.bus_ids(:)' == 9,1);
assert(~isempty(bus9),'generate_ieee14_compare_bus9_pages:noBus9', ...
    'The published bus list carries no bus 9.');
assert(isequal(Ra.bus_ids(:),Rx.bus_ids(:)), ...
    'generate_ieee14_compare_bus9_pages:busListDisagreement', ...
    'The two arms publish different bus lists; bus 9 would not be one node.');
row9 = find(mpc.bus(:,1) == 9,1);
S9_pf = (mpc.bus(row9,3) + 1i*mpc.bus(row9,4))/mpc.baseMVA;
V9_pf = abs(sys.pf.bus_voltage(bus9));
y9 = conj(S9_pf)/(V9_pf^2);
Ra.bus9_row = bus9;
Rx.bus9_row = bus9;
end

% ==========================================================================
function b = bus9_signals(r,y9,determined_rad)
%BUS9_SIGNALS  Bus-9 voltage, shunt power and the bus's OWN frequency.
%
%   All four traces come from the accepted trajectory of ONE arm, on that arm's own
%   sample grid. Nothing is interpolated onto another grid, decimated or filtered.
%
%     Vm  |V_9(t)|                      from bus_voltage_magnitude directly
%     P,Q real/imag of |V_9|^2 * conj(y_9 + 1_fault/Z_f); y_9 is the case-folded load
%         admittance passed in, and the fault term is present exactly on the samples
%         the run labels 'fault' -- the same topology label the integrator used to
%         select Yfault. No load step exists on this schedule, so the live multiplier
%         is 1 everywhere (asserted by the caller).
%     f   f_0 + (1/2pi) d(theta_9)/dt, from the bus's OWN voltage angle. See the file
%         header for the frame, wrapping, event-jump and resolution treatment and for
%         the gates on each. Carried on its own time vector t_f, because a secant
%         belongs to the MIDPOINT of the step it spans, not to either endpoint.
t = r.t(:);
nt = numel(t);
nb = numel(r.bus_ids);
bus9 = r.bus9_row;
assert(isequal(size(r.bus_voltage_magnitude),[nb nt]), ...
    'generate_ieee14_compare_bus9_pages:voltageShape', ...
    'bus_voltage_magnitude is %s for %d buses over %d samples.', ...
    mat2str(size(r.bus_voltage_magnitude)),nb,nt);
Vm = abs(r.bus_voltage_magnitude(bus9,:)).';

lab = r.topology_history(:);
assert(numel(lab) == nt, ...
    'generate_ieee14_compare_bus9_pages:topologyLength', ...
    'topology_history has %d entries for %d samples.',numel(lab),nt);
in_fault = strcmp(lab,'fault');
assert(any(in_fault),'generate_ieee14_compare_bus9_pages:noFaultSamples', ...
    'No sample carries the fault topology label; the fault window is missing.');
Zf = r.sched.Zf;
S9t = (Vm.^2).*conj(y9 + in_fault*(1/Zf));

[fv,tf,fdiag] = bus_frequency(r,bus9,Vm,determined_rad);

b = struct('t',t,'Vm',Vm,'P',real(S9t),'Q',imag(S9t), ...
    't_f',tf,'f',fv,'f_diag',fdiag,'n_samples',nt);
end

% ==========================================================================
function [f,tf,diag] = bus_frequency(r,bus9,Vm_pub,determined_rad)
%BUS_FREQUENCY  The frequency AT one bus, from that bus's own voltage angle.
%
%   f_9(t) = f_0 + (1/2pi) d(theta_9)/dt, as the secant slope of the UNWRAPPED angle
%   across each accepted step, carried at the step's midpoint. Bus 9 has no device, so
%   no frequency is a state there and none is published; this is the only frequency
%   that bus has, and it is derived from a solved algebraic variable of the run rather
%   than from any device's estimate.
%
%   The complex bus voltage is reconstructed from y_traj, whose rows INTERLEAVE the
%   real and imaginary part of each bus voltage. That layout is not assumed: the
%   reconstructed magnitude is checked against the run's own published
%   bus_voltage_magnitude to EXACTLY zero, so a different packing (or a different bus
%   ordering) cannot pass unnoticed.
%
%   Three things are removed rather than divided through:
%     * zero-length steps -- an event publishes a left and a right sample at ONE
%       instant, and a difference across that pair is a jump, not a rate
%     * the wrap -- the angle is unwrapped before differencing
%     * unresolved steps -- a secant can only express an angle motion below pi, so a
%       step whose |d theta| reaches DETERMINED_RAD is returned as NaN and drawn as a
%       gap. How many, and how much time they cover, is reported.
ny = size(r.y_traj,1);
assert(mod(ny,2) == 0 && ny/2 == numel(r.bus_ids), ...
    'generate_ieee14_compare_bus9_pages:networkStateShape', ...
    ['y_traj has %d rows for %d buses; the bus voltage layout this page reads ' ...
     '(two interleaved rows per bus) does not hold.'],ny,numel(r.bus_ids));
V = r.y_traj(1:2:end,:) + 1i*r.y_traj(2:2:end,:);
resid = max(abs(abs(V) - r.bus_voltage_magnitude),[],'all');
assert(resid == 0, ...
    'generate_ieee14_compare_bus9_pages:networkStateLayout', ...
    ['Reconstructing the bus voltages from y_traj does not reproduce the run''s own ' ...
     'bus_voltage_magnitude (max difference %.3e). The rows this page reads as ' ...
     'bus 9''s real and imaginary part are not that bus''s voltage, so an angle rate ' ...
     'taken from them would not be its frequency.'],resid);
assert(max(abs(abs(V(bus9,:)).' - Vm_pub)) == 0, ...
    'generate_ieee14_compare_bus9_pages:busRowMismatch', ...
    'The reconstructed bus-9 row does not match the published bus-9 magnitude.');

f0 = 60;
if isfield(r,'agsi_reference') && isstruct(r.agsi_reference) && ...
        isfield(r.agsi_reference,'bases') && ...
        isfield(r.agsi_reference.bases,'f0_Hz')
    f0 = double(r.agsi_reference.bases.f0_Hz);
end
assert(isfinite(f0) && f0 > 0, ...
    'generate_ieee14_compare_bus9_pages:nominalFrequencyUnrecorded', ...
    'The arm records no usable nominal frequency; f_9 is a deviation from one.');

t = r.t(:);
th = unwrap(angle(V(bus9,:)).');
dt = diff(t);
dth = diff(th);
tf = (t(1:end-1) + t(2:end))/2;
live = dt > 0;
det = live & abs(dth) < determined_rad;
f = nan(numel(tf),1);
f(det) = f0 + (dth(det)./dt(det))/(2*pi);

% THE FRAME GATE's raw material: before the first event the system is synchronous, so
% bus 9's angle must be stationary in the run's own frame. The caller asserts on this.
t_ev = NaN;
if isfield(r.sched,'sg_trip'), t_ev = double(r.sched.sg_trip); end
pre = det & tf < t_ev;

diag = struct();
diag.f0_Hz = f0;
diag.n_steps = numel(tf);
diag.n_zero_length = sum(~live);
diag.n_determined = sum(det);
diag.n_undetermined = sum(live & ~det);
diag.undetermined_seconds = sum(dt(live & ~det));
diag.total_seconds = sum(dt(live));
diag.max_abs_dtheta_rad = max(abs(dth(live)));
diag.determined_rad = determined_rad;
diag.n_raw_wraps = sum(abs(diff(angle(V(bus9,:)).')) > determined_rad);
diag.grid_bound_min_Hz = min(1./(2*dt(live)));
diag.n_pre_event = sum(pre);
diag.pre_event_max_abs_dtheta_rad = max_or(abs(dth(pre)),NaN);
diag.pre_event_f_range = finite_range(f(pre));
diag.f_range_determined = finite_range(f(det));
end

% ==========================================================================
function frequency_frame_gate(B,afile,xfile)
%FREQUENCY_FRAME_GATE  An angle rate is a frequency only in a frame rotating at f_0.
%   Before the first event both arms are synchronous, so bus 9's angle must be
%   STATIONARY and f_9 must come out at exactly the nominal. Measured on both delivered
%   arms: |d theta_9| = 0.000e+00 rad over every pre-trip step, f_9 = 60.000000000 Hz.
%   A frame that rotated at anything else -- or a y_traj row that was not this bus --
%   would fail here rather than produce a plausible-looking trace.
FRAME_TOL = 1e-9;
files = struct('adaptive',afile,'fixed',xfile);
for nm = {'adaptive','fixed'}
    d = B.(nm{1}).f_diag;
    assert(d.n_pre_event > 0, ...
        'generate_ieee14_compare_bus9_pages:noPreEventSamples', ...
        ['Arm %s (%s) has no determined bus-9 frequency sample before its first ' ...
         'event, so the frame the angle rate is measured in cannot be verified.'], ...
        nm{1},files.(nm{1}));
    dev = max(abs(d.pre_event_f_range - d.f0_Hz));
    assert(dev <= FRAME_TOL, ...
        'generate_ieee14_compare_bus9_pages:frequencyFrameGate', ...
        ['Arm %s (%s): before its first event bus 9''s derived frequency spans ' ...
         '[%.9f %.9f] Hz, %.3e off the nominal %.6f Hz (tolerance %.1e). The ' ...
         'system is synchronous there, so the bus angle must be stationary in the ' ...
         'run''s frame; a nonzero rate means the angle rate this page draws is not ' ...
         'a frequency in that frame.'],nm{1},files.(nm{1}), ...
         d.pre_event_f_range(1),d.pre_event_f_range(2),dev,d.f0_Hz,FRAME_TOL);
end
fprintf(['bus-9 frequency frame gate on BOTH arms: f_9 = %.9f Hz before the first ' ...
    'event\n'],B.adaptive.f_diag.f0_Hz);
for nm = {'adaptive','fixed'}
    d = B.(nm{1}).f_diag;
    fprintf(['  %-8s %d of %d step(s) determined (|dtheta| < %.4f rad); %d ' ...
        'undetermined = %.3f s of %.3f s; grid bound %.2f Hz\n'],nm{1}, ...
        d.n_determined,d.n_steps,d.determined_rad,d.n_undetermined, ...
        d.undetermined_seconds,d.total_seconds,d.grid_bound_min_Hz);
end
end

% ==========================================================================
function identity_gate(B,S9_pf,V9_pf,afile,xfile)
%IDENTITY_GATE  Before the first event both arms sit on the PF operating point.
%   So the reconstructed bus-9 power must reproduce the case's published load and the
%   PF voltage to solver precision. This is what makes the panels a measurement of
%   bus 9 rather than a plausible-looking trace.
files = struct('adaptive',afile,'fixed',xfile);
for nm = {'adaptive','fixed'}
    b = B.(nm{1});
    assert(abs(b.P(1)-real(S9_pf)) < 1e-9 && ...
        abs(b.Q(1)-imag(S9_pf)) < 1e-9 && abs(b.Vm(1)-V9_pf) < 1e-9, ...
        'generate_ieee14_compare_bus9_pages:bus9IdentityGate', ...
        ['Arm %s (%s) bus-9 reconstruction at t=0 gives P=%.9f Q=%.9f ' ...
         '|V|=%.9f; the case load and PF voltage are P=%.9f Q=%.9f |V|=%.9f.'], ...
        nm{1},files.(nm{1}),b.P(1),b.Q(1),b.Vm(1), ...
        real(S9_pf),imag(S9_pf),V9_pf);
end
fprintf('bus-9 identity gate at t=0 on BOTH arms: P=%.6f Q=%.6f |V|=%.6f\n', ...
    real(S9_pf),imag(S9_pf),V9_pf);
end

% ==========================================================================
function pages = draw_pages(B,opts,odir,id)
%DRAW_PAGES  The two sheets: P/Q, then |V|/f.
%   SPEC is the whole difference between them, so the two sheets cannot drift apart in
%   geometry, palette or lettering -- only in which channel each panel draws.
%
%   TSRC names the time vector a channel is carried on. P, Q and |V| are sample
%   quantities and sit on t; f_9 is a SECANT quantity and sits on t_f, the midpoints of
%   the steps it spans. Drawing it against t would put every value half a step early.
SPEC = { ...
    'cmp_pq', {
        struct('ch','P','tsrc','t','ylab','{\itP}_{Bus9} [p.u.]','tag','(a)', ...
            'zero',false,'nominal',false,'pad_events',false)
        struct('ch','Q','tsrc','t','ylab','{\itQ}_{Bus9} [p.u.]','tag','(b)', ...
            'zero',true,'nominal',false,'pad_events',false)
    }; ...
    'cmp_vf', {
        struct('ch','Vm','tsrc','t','ylab','{\itV}_{Bus9} [p.u.]','tag','(a)', ...
            'zero',false,'nominal',false,'pad_events',false)
        struct('ch','f','tsrc','t_f','ylab','{\itf}_{Bus9} [Hz]','tag','(b)', ...
            'zero',false,'nominal',true,'pad_events',true)
    }};

pages = struct('sheet',{},'png',{},'fig',{},'panels',{});
for s = 1:size(SPEC,1)
    pages(end+1) = draw_one_sheet(B,opts,odir,id,SPEC{s,1},SPEC{s,2}); %#ok<AGROW>
end
end

% ==========================================================================
function page = draw_one_sheet(B,opts,odir,id,sheet,panels)
%DRAW_ONE_SHEET  Two panels side by side under one POLICY legend.
%   The V/f and P/Q deck pages' geometry, minus the mode strip and its caption: this
%   page's blue means a policy, not IBR_1, so a per-converter strip in the IBR palette
%   would mis-attribute its own first hue. See the file header.
W = opts.width_in; H = opts.height_in;
fs = opts.font_size;
FN = char(opts.font_name);
LEFT = 0.60; RIGHT = 0.06; GAPX = 0.62;      % GAPX holds column 2's y lettering
% BOT carries the time ticks, the x label AND the panel tag under it, in that order
% down the canvas -- the tag is outside the axes, as the sibling pages have it.
BOT = 0.74; TOPLEG = 0.30;
COLW = (W - LEFT - RIGHT - GAPX)/2;
PANH = H - BOT - TOPLEG;
if PANH <= 0.35
    error('generate_ieee14_compare_bus9_pages:canvasTooShort', ...
        ['The canvas is %.2f in tall, which leaves %.2f in for the data panels ' ...
         'after the legend and the axis lettering. Raise height_in.'],H,PANH);
end

BLUE = [0.00 0.24 0.75];       % the adaptive policy
GREY = [0.45 0.45 0.45];       % every converter locked grid-following
A = B.adaptive; F = B.fixed;
xr = [0 160];
fw = opts.fault_window;

f1 = pf_page_figure(W,H,fs,opts.font_name);
x_col = [LEFT, LEFT+COLW+GAPX];
hA = gobjects(0); hF = gobjects(0);
rec = struct('channel',{},'window',{},'adaptive_range',{},'fixed_range',{}, ...
    'offscale',{},'window_excluded',{});

for k = 1:numel(panels)
    p = panels{k};
    tA = A.(p.tsrc); tF = F.(p.tsrc);
    yA = A.(p.ch); yF = F.(p.ch);
    ax = axes_in(f1,[x_col(k) BOT COLW PANH],W,H); hold(ax,'on');
    % Zero is a meaningful level for Q -- it separates absorbing from supplying -- so
    % it is drawn as a reference rule, the way the sibling P/Q page draws it.
    if p.zero
        yline(ax,0,'-','Color',[0.55 0.55 0.55],'LineWidth',0.6, ...
            'HandleVisibility','off');
    end
    % The nominal on the frequency panel, for the same reason: every value there is a
    % deviation from it.
    if p.nominal
        yline(ax,A.f_diag.f0_Hz,'-','Color',[0.55 0.55 0.55],'LineWidth',0.6, ...
            'HandleVisibility','off');
    end
    % FIXED FIRST, adaptive second: the grey arm oscillates over a wide band and would
    % otherwise cover the blue trace it is being compared against.
    gF = plot(ax,tF,yF,'Color',GREY,'LineWidth',0.7);
    gA = plot(ax,tA,yA,'Color',BLUE,'LineWidth',1.1);
    if isempty(hA), hA = gA(1); hF = gF(1); end
    % The WINDOW excludes the fault window on every panel, and on the frequency panel
    % also a margin around each switching instant: the first short step after a
    % transaction carries a genuine but very large rate (up to 136.7 Hz at the fault
    % clear on the adaptive arm), which would set an axis that flattens the comparison.
    % The samples are still DRAWN either way and any excursion is annotated at the
    % frame -- only the window ignores them.
    [wA,exA] = window_mask(tA,fw,p.pad_events,opts);
    [wF,exF] = window_mask(tF,fw,p.pad_events,opts);
    yl = shared_window(yA(wA,:),yF(wF,:),panel_extras(p,A.f_diag.f0_Hz),0.06);
    ylim(ax,yl);
    xlim(ax,xr);
    finish_panel(ax,fs,FN,p.ylab,'{\itt} [s]',p.tag);
    oA = mark_offscale(ax,tA,yA,yl,xr,BLUE,FN,fs-2.5,'%.2f','right');
    oF = mark_offscale(ax,tF,yF,yl,xr,GREY,FN,fs-2.5,'%.2f','left');
    assert_nothing_hidden(ax,yl,exA,exF,p.ch);
    rec(end+1) = struct('channel',p.ch,'window',yl, ...
        'adaptive_range',finite_range(yA),'fixed_range',finite_range(yF), ...
        'offscale',[oA oF], ...
        'window_excluded',[sum(~wA) sum(~wF)]); %#ok<AGROW>
end

% One legend for both columns, naming the two POLICIES -- not four converters. Built
% from explicit handles: the frequency panel draws four traces per arm, so relying on
% HandleVisibility would let the legend pick an arbitrary one.
lg = legend([hA hF],{'{\itAdaptive GFL/GFM}','{\itFixed GFL}'}, ...
    'Orientation','horizontal','Box','off','FontName',FN,'FontSize',fs-2, ...
    'Interpreter','tex');
assert(numel(lg.String) == 2, ...
    'generate_ieee14_compare_bus9_pages:legendEntries', ...
    'The comparison legend must carry exactly two policy entries.');
lg.Units = 'inches';
lg.Position = [LEFT + (W-LEFT-RIGHT-lg.Position(3))/2, ...
    H - TOPLEG + 0.04, lg.Position(3), lg.Position(4)];

png = fullfile(odir,sprintf('%s_%s.png',id,sheet));
pf_page_export(f1,png,opts.dpi,opts.save_fig);
figf = '';
if opts.save_fig
    figf = fullfile(odir,sprintf('%s_%s.fig',id,sheet));
end
page = struct('sheet',sheet,'png',png,'fig',figf,'panels',rec);
end

% ==========================================================================
function e = panel_extras(p,f0)
%PANEL_EXTRAS  Reference levels a panel draws, which its window must contain.
%   A reference rule that fell outside its own panel would be a reference the reader
%   cannot see, so the level is passed into the window computation rather than hoped
%   to be inside it.
e = [];
if p.zero, e = [e; 0]; end
if p.nominal, e = [e; f0]; end
end

% ==========================================================================
function [keep,excl] = window_mask(t,fw,pad_events,opts)
%WINDOW_MASK  Which samples of one arm SET a panel's y window.
%   Never which samples are drawn -- every sample is drawn. KEEP selects what the
%   window is computed over; EXCL is the complementary set of time intervals, which
%   assert_nothing_hidden then allows to leave the axes because mark_offscale annotates
%   whatever does.
%
%   The fault window always comes out: a bolted fault drives every channel far past its
%   operating band. PAD_EVENTS additionally removes a margin around each switching
%   instant, which the frequency panel needs and the others do not -- an algebraic state
%   jumps at a transaction, so the first short step after one carries a very large but
%   entirely genuine rate.
t = t(:);
excl = [fw(1) fw(2)];
keep = ~(t >= fw(1) & t <= fw(2));
if pad_events
    for e = opts.event_times
        a = e - opts.event_pad; b = e + opts.event_pad;
        keep = keep & ~(t >= a & t <= b);
        excl = [excl; a b]; %#ok<AGROW>
    end
end
end

% ==========================================================================
function ax = axes_in(f,rect_in,W,H)
%AXES_IN  One axes at an explicit rectangle given in INCHES on the canvas.
%   Converted to normalized units rather than left in inches, because a figure whose
%   axes carry absolute units does not survive being resized -- and the .fig written
%   beside the PNG is meant to be reopened and adjusted.
ax = axes(f,'Units','normalized', ...
    'Position',[rect_in(1)/W rect_in(2)/H rect_in(3)/W rect_in(4)/H]);
end

% ==========================================================================
function yl = shared_window(varargin)
%SHARED_WINDOW  One y window covering every finite sample given, with headroom.
%   Used so both compared policies read on ONE scale per panel: a comparison drawn on
%   two scales is not a comparison. This sets the VIEW; no data is modified or
%   clipped, and the caller then asserts that nothing outside the declared fault
%   window falls outside the window.
headroom = varargin{end};
v = [];
for k = 1:numel(varargin)-1
    s = varargin{k}(:);
    v = [v; s(isfinite(s))]; %#ok<AGROW>
end
assert(~isempty(v),'generate_ieee14_compare_bus9_pages:emptySeries', ...
    'A panel was asked for limits over no finite samples.');
lo = min(v); hi = max(v);
pad = headroom*(hi-lo);
if pad <= 0, pad = max(0.01,headroom*abs(hi)); end
yl = [lo-pad hi+pad];
% A magnitude that never goes negative should not be given a negative axis: the
% headroom below zero would suggest a sign the quantity cannot take.
if lo >= 0 && yl(1) < 0, yl(1) = 0; end
end

% ==========================================================================
function r = finite_range(Y)
%FINITE_RANGE  [min max] over the finite samples of a channel, for provenance.
y = Y(:);
y = y(isfinite(y));
if isempty(y), r = [NaN NaN]; else, r = [min(y) max(y)]; end
end

% ==========================================================================
function v = max_or(Y,default)
%MAX_OR  The maximum of the finite entries of Y, or DEFAULT when there are none.
%   An empty maximum is [] in MATLAB, which would silently shrink a diagnostics field
%   to nothing instead of saying that nothing was measured.
y = Y(:);
y = y(isfinite(y));
if isempty(y), v = default; else, v = max(y); end
end

% ==========================================================================
function finish_panel(ax,fs,FN,ylab,xlab,tag)
%FINISH_PANEL  The standing style contract, identical to the V/f and P/Q pages':
%   no box, ticks outward, dashed major AND minor grid, deck typeface through the
%   'tex' interpreter, and NO vertical event rules.
%
%   xlim and ylim are set by the CALLER, before this is called: nothing here draws
%   into the axes, so there is no freeze-and-restore ordering to get wrong.
set(ax,'Box','off','TickDir','out','Layer','bottom', ...
    'XMinorGrid','on','YMinorGrid','on','MinorGridLineStyle','--', ...
    'MinorGridColor',[0.65 0.65 0.65],'GridLineStyle','--', ...
    'GridColor',[0.85 0.85 0.85],'TickLabelInterpreter','tex', ...
    'FontName',FN,'FontSize',fs);
grid(ax,'on');
ylabel(ax,ylab,'FontName',FN,'FontSize',fs,'Interpreter','tex');
if ~isempty(xlab)
    xlabel(ax,xlab,'FontName',FN,'FontSize',fs,'Interpreter','tex');
else
    set(ax,'XTickLabel',[]);
end
% Panel tag BELOW the x label, centred, outside the axes -- the sibling pages'
% placement. Inside the panel it has nowhere to go: both frame corners on the right
% are where the off-scale annotations land.
text(ax,0.5,-0.32,tag,'Units','normalized','Interpreter','tex', ...
    'HorizontalAlignment','center','VerticalAlignment','top', ...
    'FontName',FN,'FontSize',fs,'Clipping','off');
end

% ==========================================================================
function info = mark_offscale(ax,t,Y,yl,xr,col,FN,fs,fmt,side)
%MARK_OFFSCALE  Flag data that leaves the panel window, with its peak value.
%   A view that silently cut an excursion would misrepresent the run, so an excursion
%   past either frame is annotated AT THE FRAME with the value it reached.
%
%   ONE label per direction per ARM, at a fixed edge rather than at the peak's own
%   instant: the two arms peak within milliseconds of each other on this schedule, so
%   labels placed at their own instants printed on top of one another. The two arms
%   are given OPPOSITE edges (adaptive right, fixed left) for the same reason. Every
%   channel that left is still listed individually in the provenance file.
info = struct('arm',{},'channel',{},'peak',{},'t_peak',{},'direction',{});
if isvector(Y), Y = Y(:); end
t = t(:);
[hi,ih] = max(Y,[],1);
[lo,il] = min(Y,[],1);
[hi,c_hi] = max(hi); ih = ih(c_hi);
[lo,c_lo] = min(lo); il = il(c_lo);
arm = 'adaptive';
if strcmp(side,'left'), arm = 'fixed'; end
if strcmp(side,'right')
    x_lab = xr(1) + 0.99*(xr(2)-xr(1));
    align = 'right';
else
    x_lab = xr(1) + 0.01*(xr(2)-xr(1));
    align = 'left';
end
if isfinite(hi) && hi > yl(2)
    text(ax,x_lab,yl(2),sprintf('\\uparrow %s ',sprintf(fmt,hi)), ...
        'Interpreter','tex','Color',col,'FontName',FN,'FontSize',fs, ...
        'HorizontalAlignment',align,'VerticalAlignment','top', ...
        'BackgroundColor',[1 1 1],'Margin',0.5,'Clipping','on');
    info(end+1) = struct('arm',arm,'channel',c_hi,'peak',hi, ...
        't_peak',t(ih),'direction','above');
end
if isfinite(lo) && lo < yl(1)
    text(ax,x_lab,yl(1),sprintf('\\downarrow %s ',sprintf(fmt,lo)), ...
        'Interpreter','tex','Color',col,'FontName',FN,'FontSize',fs, ...
        'HorizontalAlignment',align,'VerticalAlignment','bottom', ...
        'BackgroundColor',[1 1 1],'Margin',0.5,'Clipping','on');
    info(end+1) = struct('arm',arm,'channel',c_lo,'peak',lo, ...
        't_peak',t(il),'direction','below');
end
end

% ==========================================================================
function assert_nothing_hidden(ax,yl,exclA,exclF,ch)
%ASSERT_NOTHING_HIDDEN  No sample may leave the window outside a declared interval.
%   Inside the intervals the window deliberately ignored -- the fault window, and on the
%   frequency panel a margin around each switching instant -- an excursion IS allowed to
%   leave the axes, and mark_offscale annotates it at the frame with its peak. A sample
%   that left the window anywhere else would be hidden without being named, which would
%   misrepresent the comparison, so that aborts before the page is written.
%
%   The two arms carry DIFFERENT excluded sets only in principle; in practice they share
%   one schedule, so both are passed and each line is checked against the union. A line
%   is matched to its arm by length, which is unambiguous here (2288 or 2287 against
%   8007 or 8006).
E = [exclA; exclF];
lines = findobj(ax,'Type','line');
for k = 1:numel(lines)
    yd = lines(k).YData(:);
    xd = lines(k).XData(:);
    keep = true(size(yd));
    if numel(xd) == numel(yd)
        for j = 1:size(E,1)
            keep = keep & ~(xd >= E(j,1) & xd <= E(j,2));
        end
    end
    yd = yd(keep);
    yd = yd(isfinite(yd));
    if isempty(yd), continue; end
    assert(min(yd) >= yl(1)-1e-9 && max(yd) <= yl(2)+1e-9, ...
        'generate_ieee14_compare_bus9_pages:clippedSeries', ...
        ['Channel %s: outside the declared interval(s) %s a plotted series spans ' ...
         '[%.6f %.6f], beyond the panel window [%.6f %.6f]; the view would hide ' ...
         'samples without annotating them.'], ...
        ch,mat2str(E,6),min(yd),max(yd),yl(1),yl(2));
end
end

% ==========================================================================
function T = measured_table(B,opts)
%MEASURED_TABLE  The scalars the slide's prose may quote, as raw samples.
%   No statistic is formed: these are minima and maxima over the accepted samples of
%   one arm over one window. The ISLAND window (20 <= t < 100 s, the machine out)
%   minus the fault window is what separates the two policies, so it is reported
%   separately from the whole run.
%
%   The frequency channel is reported over ITS OWN window as well -- determined, off
%   event -- because that is the set the panel's axis is built from, and quoting a
%   number the axis was not built from would misdescribe the page.
fw = opts.fault_window;
T = struct();
for nm = {'adaptive','fixed'}
    b = B.(nm{1});
    isl = b.t >= 20 & b.t < 100;
    outb = isl & ~(b.t >= fw(1) & b.t <= fw(2));
    e = struct();
    e.n_samples = b.n_samples;
    e.n_island_op_band = sum(outb);
    for ch = {'P','Q','Vm'}
        y = b.(ch{1});
        e.([ch{1} '_whole']) = finite_range(y);
        e.([ch{1} '_island_op_band']) = finite_range(y(outb,:));
    end
    % f_9 lives on the secant grid, so its masks are built on t_f.
    tf = b.t_f;
    fisl = tf >= 20 & tf < 100;
    fout = fisl & ~(tf >= fw(1) & tf <= fw(2));
    e.f_whole = finite_range(b.f);
    e.f_island_op_band = finite_range(b.f(fout));
    wf = window_mask(tf,fw,true,opts);
    e.f_window_set = finite_range(b.f(wf));
    e.f_island_window_set = finite_range(b.f(wf & fisl));
    e.n_f_determined = b.f_diag.n_determined;
    e.n_f_undetermined = b.f_diag.n_undetermined;
    e.f_undetermined_seconds = b.f_diag.undetermined_seconds;
    T.(nm{1}) = e;
end
end

% ==========================================================================
function t_events = schedule_times(r)
%SCHEDULE_TIMES  The four CASE_DEFINED disturbance times of one arm.
%   The sg_fault_cycle profile arms exactly these four instants
%   (sg_trip < fault_on < fault_clear < sg_on <= t_end); there is no load step, no
%   line trip and no restore_time on this schedule by design.
names = {'sg_trip','fault_on','fault_clear','sg_on'};
t_events = zeros(1,numel(names));
for k = 1:numel(names)
    assert(isfield(r.sched,names{k}) && isscalar(r.sched.(names{k})) && ...
        isfinite(r.sched.(names{k})), ...
        'generate_ieee14_compare_bus9_pages:missingSchedule', ...
        'The arm schedule lacks a finite scalar %s.',names{k});
    t_events(k) = double(r.sched.(names{k}));
end
end

% ==========================================================================
function [S,sha] = load_guarded(file)
%LOAD_GUARDED  Load a cache, refusing a read that races a concurrent writer.
sha = sha256_of(file);
S = load(file);
assert(strcmp(sha,sha256_of(file)), ...
    'generate_ieee14_compare_bus9_pages:cacheChangedWhileReading', ...
    'Cache %s changed during the read; a concurrent writer is active.',file);
end

% ==========================================================================
function v = field_or(s,name,default)
v = default;
if isstruct(s) && isfield(s,name), v = s.(name); end
end

function s = iif(c,a,b)
if c, s = a; else, s = b; end
end

% ==========================================================================
function sha = sha256_of(f)
%SHA256_OF  Hex SHA-256 of a file via Java, on an absolute path.
%   Streamed rather than read whole: the caches are tens to hundreds of megabytes.
fj = char(java.io.File(f).getCanonicalPath());
h = java.security.MessageDigest.getInstance('SHA-256');
fis = java.io.FileInputStream(fj);
try
    buf = typecast(zeros(1,65536,'int8'),'uint8');
    while true
        n = fis.read(buf);
        if n < 0, break; end
        h.update(buf(1:n));
    end
catch err
    fis.close();
    rethrow(err);
end
fis.close();
sha = sprintf('%02x',reshape(typecast(h.digest(),'uint8'),1,[]));
end

% ==========================================================================
function write_provenance(odir,out)
%WRITE_PROVENANCE  Plain-text manifest beside the two pages.
%   Same shape as the sibling pages' manifests: a key/value header, then one block per
%   sheet naming its files with SHA-256, mtime and the caches they came from, so a
%   reader holding one slide can tell which two trajectories produced it.
p = fullfile(odir,'provenance_compare_bus9_pages.txt');
fid = fopen(p,'w');
if fid < 0
    warning('generate_ieee14_compare_bus9_pages:provenanceUnwritable', ...
        'Could not write %s; the figures are still valid.',p);
    return;
end
fprintf(fid,'generator: scripts/reporting/generate_ieee14_compare_bus9_pages.m\n');
fprintf(fid,'schema:    %s\n',out.schema);
fprintf(fid,'generated: %s\n',out.generated_utc);
fprintf(fid,['style:     %g in x %g in, %s %g pt, tex interpreter, %s, box off, ' ...
    'ticks out\n'],out.style.width_in,out.style.height_in, ...
    out.style.font_name,out.style.font_size,out.style.grid);
fprintf(fid,'\n');
fprintf(fid,['TWO SHEETS, two panels each, at bus 9 -- the fault bus, which carries ' ...
    'load but NO\n  device, so it reports what the island DELIVERS to a load bus ' ...
    'rather than what any one\n  controller commands. One 160 s schedule on both ' ...
    'arms:\n    sg_trip 20 -> fault_on 60 -> fault_clear 60.15 -> sg_on 100 -> ' ...
    '160 s\n' ...
    '    <id>_cmp_pq   (a) P_Bus9    (b) Q_Bus9\n' ...
    '    <id>_cmp_vf   (a) |V_Bus9|  (b) f_Bus9\n' ...
    '  blue = the delivered adaptive GFL/GFM switching policy (PROJECT_RESULT)\n' ...
    '  grey = the same case with every converter locked grid-following\n' ...
    '         (ASSUMED_DIAGNOSTIC, comparison-only)\n\n']);
fprintf(fid,['This is the report''s 2x2 bus-9 comparison ' ...
    '(generate_bus9_adaptive_vs_fixed_160s.m)\n  SPLIT INTO TWO SLIDE PAGES and ' ...
    'restyled to match the deck''s V/f and P/Q pages, at the\n  owner''s ' ...
    'instruction (2026-09-05). Every input gate of that figure is enforced here\n' ...
    '  unchanged: classifications, both arms converged to 160 s, one shared event ' ...
    'schedule,\n  the device-to-bus mapping, one fault impedance, no load step, and ' ...
    'the t=0 bus-9\n  identity gate on BOTH arms.\n\n']);
fprintf(fid,['Pure cache reader. No step is taken, no equation is solved, and ' ...
    'nothing is smoothed,\n  filtered, decimated, clipped, offset, interpolated or ' ...
    'padded. Each arm is drawn on\n  its OWN accepted-sample grid (%d adaptive ' ...
    'against %d fixed); nothing is resampled\n  onto the other''s. No synthetic ' ...
    'augmentation layer: the fixed arm oscillates on its\n  own, so there is ' ...
    'nothing to add. LINE-ONLY -- no area, fill or patch under any\n  curve, so a ' ...
    'thin trace can never read as a thick one.\n\n'], ...
    out.n_samples(1),out.n_samples(2));
fprintf(fid,['NO MODE STRIP on these pages, unlike their two siblings. The strip''s ' ...
    'lanes are\n  per-converter in the IBR palette, whose FIRST hue is this page''s ' ...
    'blue -- and here blue\n  means a POLICY, not IBR_1. A blue bar above a blue ' ...
    'trace would read as the adaptive\n  arm''s own bar rather than as a ' ...
    'converter''s, so the strip is left to the pages where\n  colour means a ' ...
    'converter.\n\n']);
fprintf(fid,['NO VERTICAL EVENT RULES, and the panel tag sits BELOW the x label, ' ...
    'centred: the\n  styling the owner set on the V/f and P/Q pages. Every ' ...
    'scheduled instant is listed at\n  the end of this file instead.\n\n']);
fprintf(fid,['THE FREQUENCY PANEL IS THE FREQUENCY AT BUS 9 ITSELF, at the owner''s ' ...
    'instruction\n  (2026-09-05). Bus 9 carries load but NO device, so no frequency ' ...
    'is a state there and\n  none is published for it; it is DERIVED from the bus''s ' ...
    'own voltage angle, which IS a\n  solved algebraic variable of the run:\n\n' ...
    '      f_9(t) = f_0 + (1/2pi) d(theta_9)/dt\n\n' ...
    '  taken as the secant slope of the UNWRAPPED angle across each accepted step -- ' ...
    'the\n  average frequency over that step, carried at the step''s MIDPOINT (so it ' ...
    'is plotted on\n  its own time vector, not on the sample grid). BOTH arms are ' ...
    'derived the same way from\n  their own solutions, which is what makes the two ' ...
    'policies comparable here at all.\n\n' ...
    '  FOUR THINGS THAT WOULD MAKE THAT WRONG, all handled and all gated:\n' ...
    '    1. THE FRAME. An angle rate is a frequency only if the frame rotates at ' ...
    'f_0. Gated\n       by measurement: before the first event both arms are ' ...
    'synchronous, so theta_9 must\n       be STATIONARY -- and is, to ' ...
    '|d theta_9| = 0 exactly, giving f_9 = f_0 exactly.\n' ...
    '    2. WRAPPING. theta_9 is returned on (-pi, pi]; it is unwrapped BEFORE it is\n' ...
    '       differenced. Raw wrap-sized jumps per arm are counted below.\n' ...
    '    3. THE EVENT JUMP. A transaction moves the algebraic state discontinuously ' ...
    'and\n       publishes a left AND a right sample at ONE instant (dt = 0). Those ' ...
    'pairs are\n       dropped rather than divided by; the count is below.\n' ...
    '    4. RESOLUTION. A secant can only express |f - f_0| <= 1/(2 dt). Beyond a ' ...
    'half turn\n       per step the true motion is theta + 2 pi k for unknown k and ' ...
    'the number would be\n       the GRID''s bound, not the run''s. Steps whose ' ...
    '|d theta| reaches %.4f rad -- half\n       the wrap limit -- are NOT DRAWN, and ' ...
    'how many is reported below.\n\n' ...
    '  So a broken grey trace is not a missing measurement: it is drawn where that ' ...
    'arm''s own\n  output grid determines the rate and gapped where it does not, and ' ...
    'the gaps are\n  themselves a finding -- a fixed-GFL fleet moves this bus''s ' ...
    'angle faster than the run\n  recorded it.\n\n'],out.frequency.determined_rad);
fprintf(fid,'  per arm:\n');
for nm = {'adaptive','fixed'}
    d = out.frequency.(nm{1});
    fprintf(fid,['    %-8s f_0 %.6f Hz | %d step(s): %d determined, %d ' ...
        'undetermined (%.3f s of\n             %.3f s) | %d zero-length event ' ...
        'pair(s) | %d raw wrap jump(s) | max |d theta|\n             %.4f rad | ' ...
        'grid bound >= %.2f Hz | determined f_9 %s Hz\n'],nm{1},d.f0_Hz, ...
        d.n_steps,d.n_determined,d.n_undetermined,d.undetermined_seconds, ...
        d.total_seconds,d.n_zero_length,d.n_raw_wraps,d.max_abs_dtheta_rad, ...
        d.grid_bound_min_Hz,mat2str(round(d.f_range_determined,4)));
end
fprintf(fid,['  The frequency panel''s WINDOW additionally ignores +/-%.2f s around ' ...
    'each scheduled\n  instant: the first short step after a transaction carries a ' ...
    'genuine but very large\n  rate, which would set an axis that flattens the ' ...
    'comparison. Those samples are still\n  DRAWN and any excursion is annotated at ' ...
    'the frame.\n\n'],out.frequency.event_pad_s);
fprintf(fid,['Y WINDOWS cover BOTH arms over the OPERATING BAND -- the run minus ' ...
    '[%g %g] s -- with 6 %%\n  headroom, so the two policies share ONE scale per ' ...
    'panel; a comparison drawn on two\n  scales is not a comparison. Anything ' ...
    'outside is annotated AT THE FRAME with its peak\n  (adaptive at the right ' ...
    'edge, fixed at the left, because the two arms peak within\n  milliseconds of ' ...
    'each other and labels at their own instants printed over one\n  another). ' ...
    'Nothing is clipped silently: a sample leaving the window anywhere OUTSIDE\n' ...
    '  the fault window aborts the page.\n\n'], ...
    out.fault_window(1),out.fault_window(2));
fprintf(fid,['Bus-9 signals: S_9(t) = |V_9(t)|^2 * conj(y_9 + chi_f(t)/Z_f), ' ...
    'chi_f = 1 on the fault\n  topology and 0 elsewhere; y_9 = %.9f%+.9fj pu from ' ...
    'the case load table at the PF\n  operating point (S_9 = %.6f%+.6fj pu, |V_9| = ' ...
    '%.6f pu). No load step on this\n  schedule, so the live multiplier is 1 ' ...
    'everywhere. The t=0 identity gate requires the\n  reconstruction to reproduce ' ...
    'those three values within 1e-9 pu on BOTH arms.\n\n'], ...
    real(out.bus9_reference.y9),imag(out.bus9_reference.y9), ...
    real(out.bus9_reference.S9_pf),imag(out.bus9_reference.S9_pf), ...
    out.bus9_reference.V9_pf);
fprintf(fid,'adaptive arm : %s\n  sha256 %s\n',out.adaptive_cache,out.adaptive_sha);
fprintf(fid,'fixed arm    : %s\n  sha256 %s\n',out.fixed_cache,out.fixed_sha);
if all(isfinite(out.fixed_pll_gains))
    fprintf(fid,['fixed arm diagnostic opt-ins (that run only; production paths ' ...
        'untouched):\n  allow_no_vf_island=true, angle_gauge_bus=1 after ' ...
        'sg_trip+0.25 s, comparison-only clone\n  ' ...
        'ibr.eecon49_dual_mode_ideal_dc for IBR2/3/6/8, diagnostic PLL pair ' ...
        '(KpPll, KiPll) =\n  (%g, %g) on the resource table only. It may support a ' ...
        'COMPARATIVE statement and never\n  a readiness claim; the production ' ...
        'noVoltageFormingSource refusal is unchanged.\n'], ...
        out.fixed_pll_gains(1),out.fixed_pll_gains(2));
end
fprintf(fid,'\n--------------------------------------------------------------\n');
for k = 1:numel(out.pages)
    g = out.pages(k);
    fprintf(fid,'%s\n',g.sheet);
    for a = {g.png,g.fig}
        if isempty(a{1}), continue; end
        if isfile(a{1})
            dd = dir(a{1});
            fprintf(fid,'  file       %s\n',a{1});
            fprintf(fid,'    sha256   %s\n',sha256_of(a{1}));
            fprintf(fid,'    mtime    %s\n',char(datetime(dd.datenum, ...
                'ConvertFrom','datenum','Format','yyyy-MM-dd HH:mm:ss')));
            fprintf(fid,'    bytes    %d\n',dd.bytes);
        else
            fprintf(fid,'  file       %s (MISSING)\n',a{1});
        end
    end
    for j = 1:numel(g.panels)
        q = g.panels(j);
        fprintf(fid,'  panel %-3s window %s\n',q.channel,mat2str(q.window,6));
        fprintf(fid,'            adaptive %s   fixed %s (whole run)\n', ...
            mat2str(q.adaptive_range,6),mat2str(q.fixed_range,6));
        fprintf(fid,['            %d adaptive and %d fixed sample(s) drawn but ' ...
            'excluded from the window\n'],q.window_excluded(1), ...
            q.window_excluded(2));
        if isempty(q.offscale)
            fprintf(fid,'            offscale none: every sample is inside\n');
        end
        for m = 1:numel(q.offscale)
            o = q.offscale(m);
            fprintf(fid,['            offscale %-8s %-5s channel %d ' ...
                '%12.6f at t = %.6f s\n'],o.arm,o.direction,o.channel, ...
                o.peak,o.t_peak);
        end
    end
    fprintf(fid,'\n');
end
fprintf(fid,'--------------------------------------------------------------\n');
fprintf(fid,['MEASURED SCALARS, raw samples over one window of one arm -- no ' ...
    'statistic is formed.\n  The ISLAND window (20 <= t < 100 s, the machine out) ' ...
    'minus the fault window is what\n  separates the two policies, so it is ' ...
    'reported beside the whole run.\n']);
for nm = {'adaptive','fixed'}
    e = out.measured.(nm{1});
    fprintf(fid,'%s\n',nm{1});
    fprintf(fid,'  samples    %d accepted, %d in the island operating band\n', ...
        e.n_samples,e.n_island_op_band);
    for ch = {'P','Q','Vm'}
        fprintf(fid,'  %-3s        island op band %s   whole run %s\n',ch{1}, ...
            mat2str(e.([ch{1} '_island_op_band']),6), ...
            mat2str(e.([ch{1} '_whole']),6));
    end
    fprintf(fid,['  f_9        %d determined step(s), %d undetermined (%.3f s not ' ...
        'drawn)\n'],e.n_f_determined,e.n_f_undetermined, ...
        e.f_undetermined_seconds);
    fprintf(fid,'             island op band %s   whole run %s\n', ...
        mat2str(e.f_island_op_band,6),mat2str(e.f_whole,6));
    fprintf(fid,['             THE PANEL''S OWN WINDOW SET (determined, off event): ' ...
        '%s\n             island subset %s\n'], ...
        mat2str(e.f_window_set,6),mat2str(e.f_island_window_set,6));
end
fprintf(fid,'\nEvent times (CASE_DEFINED, s), NOT drawn on either sheet: %s\n', ...
    mat2str(out.t_events));
fprintf(fid,'  %s\n',strjoin({'sg_trip','fault_on','fault_clear','sg_on'},', '));
fclose(fid);
fprintf('wrote %s\n',p);
end
