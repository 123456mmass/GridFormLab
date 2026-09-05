function out = generate_bus9_adaptive_vs_fixed_160s(opts)
%GENERATE_BUS9_ADAPTIVE_VS_FIXED_160S  2x2 bus-9 comparison on the 160 s full cycle.
%
%   out = generate_bus9_adaptive_vs_fixed_160s()
%
% Draws the comparison figure the owner asked for: the delivered adaptive
% switching policy (blue) against the same case with every converter locked
% grid-following (grey), on ONE schedule --
%     sg_trip 20 -> fault_on 60 -> fault_clear 60.15 -> sg_on 100 -> 160 s
% at bus 9, the fault bus:
%   (a) P_Bus9  (b) Q_Bus9  (c) |V_Bus9|  (d) f_Bus9
%
% PANEL (d) IS THE FREQUENCY AT BUS 9 ITSELF, at the owner's instruction
% (2026-09-05), not any device's published frequency. Bus 9 carries load but no
% device, so no frequency is a state there and none is published for it; it is
% DERIVED from that bus's own voltage angle, which IS a solved algebraic
% variable of the run:
%
%     f_9(t) = f_0 + (1/2pi) d(theta_9)/dt
%
% taken as the secant slope of the UNWRAPPED angle across each accepted step and
% carried at the step's MIDPOINT, so it is plotted on its own time vector rather
% than on the sample grid. BOTH arms are derived the same way from their own
% solutions, which is what makes the panel a comparison at all -- the previous
% panel (d) drew each arm's device-published frequency, and a locked-GFL fleet
% publishes none once the machine is out, so that panel had no grey trace to
% compare against. The derivation and its four gates are documented on
% BUS_FREQUENCY below.
%
% INPUT ARTIFACTS (no simulation is run here)
%   output/diagnostics/ieee14_scenario_suite/sg_fault_cycle160.mat
%       the delivered PROJECT_RESULT arm (converged to 160 s, 2288 samples).
%   output/diagnostics/ieee14_locked_gfl_diag/locked_gfl_diag_160s.mat
%       the all-GFL continuation on the SAME schedule, produced by
%       scripts/diagnostics/run_locked_gfl_diag_160s.m with the diagnostic PLL
%       pair (KpPll 0.20, KiPll 220.00). Classification ASSUMED_DIAGNOSTIC: it
%       runs with the opt-in allow_no_vf_island suspension and the
%       angle_gauge_bus=1 slack-gauge pin. The production
%       noVoltageFormingSource refusal is unchanged. It may support a
%       comparative statement only, never a readiness claim.
%
% CONTRACT
%   - Pure cache reader: no simulation, no write-back. The two arms carry
%     DIFFERENT accepted-sample grids (2288 adaptive against 8007 fixed), so
%     each is drawn on its own t and never resampled onto the other's.
%   - The trajectories are NEVER modified. No smoothing, filtering, decimation,
%     interpolation, offset or resampling; no synthetic augmentation layer.
%     The fixed-GFL arm oscillates on its own (V9 peak-to-peak about 1.4 pu
%     over the island window), so there is nothing to add.
%   - LINE-ONLY drawing: no area, fill or patch under any curve.
%   - LETTERING: every text object uses the LaTeX interpreter, rates; no box,
%     ticks outward, dashed major and minor grid.
%   - Fail-closed: every assert aborts before any file is written.
%
% Regenerate with:
%   pf_init_paths; generate_bus9_adaptive_vs_fixed_160s()

arguments
    opts.adaptive_cache (1,1) string = ...
        fullfile('output','diagnostics','ieee14_scenario_suite', ...
                 'sg_fault_cycle160.mat')
    opts.fixed_cache (1,1) string = ...
        fullfile('output','diagnostics','ieee14_locked_gfl_diag', ...
                 'locked_gfl_diag_160s.mat')
    opts.out_dir (1,1) string = fullfile('docs','source','figures', ...
        'ieee14_scenario_suite')
    opts.dpi (1,1) double {mustBePositive} = 300
    % Native canvas size: the report includes this page at 1:1, so its
    % lettering arrives as set. 5.768 in is the report text width.
    opts.width_in (1,1) double {mustBePositive} = 5.768
    opts.height_in (1,1) double {mustBePositive} = 3.00
    opts.font_size (1,1) double {mustBePositive} = 11
    opts.save_fig (1,1) logical = true
    % Fault window excluded from the Y WINDOW, never from the data: the bolted
    % fault drives every channel far outside its operating band, so a window
    % containing it compresses the whole islanded comparison. Anything that
    % leaves the window is annotated at the frame with its peak value.
    opts.fault_window (1,2) double = [60 60.20]
    % DETERMINED_RAD is panel (d)'s resolution gate: a secant over one accepted
    % step can only express an angle motion below pi, so a step whose |d theta|
    % reaches this bound is returned as NaN and drawn as a gap rather than as
    % the grid's own bound. pi/2 is half the wrap limit, a factor-of-two margin.
    opts.determined_rad (1,1) double {mustBePositive} = pi/2
    % EVENT_PAD keeps panel (d)'s WINDOW off the switching instants. An event
    % moves the algebraic state discontinuously, so the first short step after
    % one carries a genuine but very large rate; a window containing it would
    % flatten the whole comparison. Those samples are still DRAWN, and anything
    % leaving the window is annotated at the frame with its peak.
    opts.event_pad (1,1) double {mustBeNonnegative} = 0.25
end

pf_init_paths();
afile = char(opts.adaptive_cache);
xfile = char(opts.fixed_cache);
odir  = char(opts.out_dir);
if ~isfolder(odir), mkdir(odir); end

% --- load, guarded against a concurrent writer -----------------------------
[Sa,sha_a] = load_guarded(afile,'');
[Sx,sha_x] = load_guarded(xfile,'');
% The adaptive suite cache nests its classification inside the stored arm
% (result carries the trajectory; arm carries the runner's record), while the
% fixed-arm cache carries its own top-level classification field. Read each
% from where its writer put it -- not from where the other one keeps it.
acl = '';
if isfield(Sa,'arm') && isstruct(Sa.arm) && isfield(Sa.arm,'classification')
    acl = char(string(Sa.arm.classification));
end
assert(strcmp(acl,'PROJECT_RESULT'), ...
    'generate_bus9_adaptive_vs_fixed_160s:adaptiveClassification', ...
    'Adaptive cache arm classification is "%s", expected PROJECT_RESULT.',acl);
assert(strcmp(char(string(Sx.classification)),'ASSUMED_DIAGNOSTIC'), ...
    'generate_bus9_adaptive_vs_fixed_160s:fixedClassification', ...
    ['Fixed-GFL cache classification is "%s"; this figure may only draw an ' ...
     'ASSUMED_DIAGNOSTIC continuation here.'],char(string(Sx.classification)));
Ra = Sa.result;
Rx = Sx.result;
assert(logical(Ra.converged) && abs(Ra.t(end)-160)<5e-4, ...
    'generate_bus9_adaptive_vs_fixed_160s:adaptiveOutcome', ...
    'Adaptive arm ends at %.6f s (converged %d), expected 160 s.', ...
    Ra.t(end),logical(Ra.converged));
assert(logical(Rx.converged) && abs(Rx.t(end)-160)<5e-4, ...
    'generate_bus9_adaptive_vs_fixed_160s:fixedOutcome', ...
    'Fixed-GFL arm ends at %.6f s (converged %d), expected 160 s.', ...
    Rx.t(end),logical(Rx.converged));
assert(strcmp(sha_a,sha256_of(afile)) && strcmp(sha_x,sha256_of(xfile)), ...
    'generate_bus9_adaptive_vs_fixed_160s:inputChangedWhileReading', ...
    'A generated input changed during this run; a concurrent writer is active.');

% --- one schedule on both arms ----------------------------------------------
t_events = schedule_times(Ra);
assert(isequal(t_events,schedule_times(Rx)), ...
    'generate_bus9_adaptive_vs_fixed_160s:scheduleDisagreement', ...
    'The adaptive and fixed arms do not share one event schedule.');
assert(max(abs(t_events-[20 60 60.15 100]))<1e-10, ...
    'generate_bus9_adaptive_vs_fixed_160s:scheduleMismatch', ...
    'Event schedule differs from the sg_fault_cycle160 [20 60 60.15 100] s.');
assert(isequal(Ra.device_bus_ids(:)',[1 2 3 6 8]), ...
    'generate_bus9_adaptive_vs_fixed_160s:deviceMappingMismatch', ...
    'Adaptive arm does not map resources 1..5 to buses [1 2 3 6 8].');
assert(isequal(Rx.device_bus_ids(:)',[1 2 3 6 8]), ...
    'generate_bus9_adaptive_vs_fixed_160s:deviceMappingMismatch', ...
    'Fixed-GFL arm does not map resources 1..5 to buses [1 2 3 6 8].');
assert(isequal(Ra.sched.Zf,Rx.sched.Zf), ...
    'generate_bus9_adaptive_vs_fixed_160s:faultImpedance', ...
    'The two arms disagree on the fault impedance.');

% --- bus-9 shunt admittance, from the CASE, not the trajectory ---------------
case_data = cases.case_ieee14bus_eecon49_switch();
mpc = case_data.mpc;
sys = ibr.build_ieee14_switch_system(index_mode='agsi_pp', ...
    case_profile='eecon49_figure4',sg_H=2.5,sg_D=1.0,T_d_on=0.10,T_d_off=1.0);
bus9 = find(Ra.bus_ids(:)'==9,1);
assert(~isempty(bus9),'generate_bus9_adaptive_vs_fixed_160s:noBus9', ...
    'The published bus list carries no bus 9.');
row9  = find(mpc.bus(:,1)==9,1);
S9_pf = (mpc.bus(row9,3) + 1i*mpc.bus(row9,4))/mpc.baseMVA;
V9_pf = abs(sys.pf.bus_voltage(bus9));
y9    = conj(S9_pf)/(V9_pf^2);

% No load step on this schedule: the runner's sg_fault_cycle160 row clears every
% load field (run_ieee14_scenario_suite.m:350), so neither arm may carry one. A
% present-but-zero factor is the same statement, hence the tolerance for 0; a
% nonzero one would put a live multiplier on S_9 and the identity gate below
% would be checking the wrong value.
for nm = {'Ra','Rx'}
    r = eval(nm{1});
    lf = [];
    if isfield(r.sched,'load_step_factor') && ~isempty(r.sched.load_step_factor)
        lf = double(r.sched.load_step_factor);
        lf = lf(isfinite(lf));
    end
    assert(isempty(lf) || all(lf==0), ...
        'generate_bus9_adaptive_vs_fixed_160s:unexpectedLoadStep', ...
        'Arm %s carries a nonzero load-step factor; this schedule has none.',nm{1});
end

B = struct();
B.adaptive = bus9_signals(Ra,y9,bus9,opts.determined_rad);
B.fixed    = bus9_signals(Rx,y9,bus9,opts.determined_rad);

% t=0 IDENTITY GATE. Before the first event both arms sit on the PF operating
% point, so the reconstructed bus-9 power must reproduce the case's published
% load and the PF voltage to solver precision.
for nm = {'adaptive','fixed'}
    b = B.(nm{1});
    assert(abs(b.P(1)-real(S9_pf))<1e-9 && abs(b.Q(1)-imag(S9_pf))<1e-9 && ...
        abs(b.Vm(1)-V9_pf)<1e-9, ...
        'generate_bus9_adaptive_vs_fixed_160s:bus9IdentityGate', ...
        ['Arm %s bus-9 reconstruction at t=0 gives P=%.9f Q=%.9f |V|=%.9f; ' ...
         'the case load and PF voltage are P=%.9f Q=%.9f |V|=%.9f.'], ...
        nm{1},b.P(1),b.Q(1),b.Vm(1),real(S9_pf),imag(S9_pf),V9_pf);
end
fprintf('bus-9 identity gate at t=0: P=%.6f  Q=%.6f  |V|=%.6f  (case/PF values)\n', ...
    real(S9_pf),imag(S9_pf),V9_pf);

% FREQUENCY FRAME GATE. An angle rate is a frequency only in a frame rotating at
% f_0, so panel (d)'s derivation is checked by measurement before it is drawn.
frequency_frame_gate(B,afile,xfile);

% --- measured scalars for the report prose (raw samples, no statistics) -------
fw = opts.fault_window;
for nm = {'adaptive','fixed'}
    b = B.(nm{1});
    isl = b.t>=20 & b.t<100;
    outb = isl & ~(b.t>=fw(1) & b.t<=fw(2));
    fprintf(['[%s] V9 island-op-band %.6f..%.6f pu | V9 whole %.6f..%.6f | ' ...
        'P9 op-band %.6f..%.6f | Q9 op-band %.6f..%.6f\n'],nm{1}, ...
        min(b.Vm(outb)),max(b.Vm(outb)),min(b.Vm),max(b.Vm), ...
        min(b.P(outb)),max(b.P(outb)),min(b.Q(outb)),max(b.Q(outb)));
    % f_9 lives on the secant grid, so its window is built on t_f -- and over
    % the set the panel's own axis is built from (determined, off event),
    % because quoting a band the axis does not show would not be this figure's
    % number.
    [kf,~] = window_mask(b.t_f,fw,true,opts,t_events);
    islf = b.t_f>=20 & b.t_f<100;
    fprintf(['[%s] f9 panel window %.4f..%.4f Hz | f9 island %.4f..%.4f | ' ...
        'f9 whole %.4f..%.4f Hz (%d of %d step(s) determined)\n'],nm{1}, ...
        min(b.f(kf)),max(b.f(kf)), ...
        min(b.f(islf & kf)),max(b.f(islf & kf)), ...
        b.f_diag.f_range_determined(1),b.f_diag.f_range_determined(2), ...
        b.f_diag.n_determined,b.f_diag.n_steps);
end

% --- draw --------------------------------------------------------------------
png = draw_bus9_compare(B,opts,t_events,odir);

% --- provenance ----------------------------------------------------------------
prov = fullfile(odir,'provenance_bus9_compare.txt');
fid = fopen(prov,'w');
fprintf(fid,'generator: scripts/reporting/generate_bus9_adaptive_vs_fixed_160s.m\n');
fprintf(fid,'schema:    bus9_adaptive_vs_fixed_160s/1.0\n');
fprintf(fid,'generated: %s\n',char(datetime('now','TimeZone','UTC', ...
    'Format','yyyy-MM-dd''T''HH:mm:ssXXX')));
fprintf(fid,'style:     %g in x %g in, Times New Roman %g pt, latex interpreter, dashed major and minor grid, box off, ticks out\n', ...
    opts.width_in,opts.height_in,opts.font_size);
fprintf(fid,'\n');
fprintf(fid,['2x2 comparison at bus 9 (the fault bus) on ONE 160 s schedule\n' ...
    '  sg_trip 20 -> fault_on 60 -> fault_clear 60.15 -> sg_on 100 -> 160 s:\n' ...
    '    (a) P_Bus9  (b) Q_Bus9  (c) |V_Bus9|  (d) f_Bus9\n' ...
    '  blue = delivered adaptive GFL/GFM switching policy (PROJECT_RESULT)\n' ...
    '  grey = same case with every converter locked grid-following\n' ...
    '         (ASSUMED_DIAGNOSTIC comparison-only continuation)\n\n']);
fprintf(fid,['Pure cache reader. No step is taken, no equation is solved, and\n' ...
    'nothing is smoothed, filtered, decimated, clipped, offset, interpolated\n' ...
    'or padded. Each arm is drawn on its OWN accepted-sample grid (%d adaptive\n' ...
    'against %d fixed samples); nothing is resampled. No synthetic augmentation\n' ...
    'layer: the fixed-GFL arm swings 0.007..1.411 pu on V9 over the island\n' ...
    'window on its own, so there is nothing to add.\n\n'], ...
    numel(Ra.t),numel(Rx.t));
fprintf(fid,'adaptive arm : %s\n  sha256 %s\n',afile,sha_a);
fprintf(fid,'fixed arm    : %s\n  sha256 %s\n',xfile,sha_x);
fprintf(fid,['fixed arm diagnostic opt-ins (this run only; production paths\n' ...
    '  untouched): allow_no_vf_island=true, angle_gauge_bus=1 after sg_trip+0.25 s,\n' ...
    '  comparison-only clone ibr.eecon49_dual_mode_ideal_dc for IBR2/3/6/8,\n' ...
    '  diagnostic PLL pair (KpPll, KiPll) = (%g, %g) on the resource table only.\n'], ...
    Sx.pll_gains(1),Sx.pll_gains(2));
fprintf(fid,['Bus-9 signals: S_9(t) = |V_9(t)|^2 * conj(y_9 + chi_f(t)/Z_f),\n' ...
    '  chi_f = 1 on the fault topology and 0 elsewhere; y_9 = %.9f%+.9fj pu\n' ...
    '  from the case load table at the PF operating point\n' ...
    '  (S_9 = %.6f%+.6fj pu, |V_9| = %.6f pu). No load step on this schedule,\n' ...
    '  so the live multiplier is 1 everywhere. The t=0 identity gate requires\n' ...
    '  the reconstruction to reproduce those three values within 1e-9 pu on\n' ...
    '  BOTH arms; it passed.\n'],real(y9),imag(y9),real(S9_pf),imag(S9_pf),V9_pf);
fprintf(fid,['Panel (d) IS THE FREQUENCY AT BUS 9 ITSELF, not any device''s:\n' ...
    '  bus 9 carries load but no device, so no frequency is a state there and\n' ...
    '  none is published for it. It is DERIVED from that bus''s own voltage\n' ...
    '  angle, which IS a solved algebraic variable of the run:\n' ...
    '      f_9(t) = f_0 + (1/2pi) d(theta_9)/dt\n' ...
    '  as the secant slope of the UNWRAPPED angle across each accepted step,\n' ...
    '  carried at the step''s MIDPOINT (so it is plotted on its own time\n' ...
    '  vector, not on the sample grid). BOTH arms are derived the same way\n' ...
    '  from their own solutions, which is what makes the panel a comparison.\n' ...
    '  Four gates hold before it draws: THE FRAME (before the first event both\n' ...
    '  arms are synchronous, so theta_9 must be stationary -- measured\n' ...
    '  f_9 = %.9f Hz exactly), WRAPPING (unwrapped before differencing),\n' ...
    '  THE EVENT JUMP (an event publishes a left and a right sample at one\n' ...
    '  instant, dt = 0; those pairs are dropped rather than divided by), and\n' ...
    '  RESOLUTION (a secant can only express |f - f_0| <= 1/(2 dt), so a step\n' ...
    '  whose |d theta| reaches %.4f rad is NOT DRAWN).\n' ...
    '  A broken grey trace is therefore not a missing measurement: it is drawn\n' ...
    '  where that arm''s own output grid determines the rate and gapped where it\n' ...
    '  does not, and the gaps are themselves a finding -- a fixed-GFL fleet\n' ...
    '  moves this bus''s angle faster than the run recorded it.\n'], ...
    B.adaptive.f_diag.f0_Hz,opts.determined_rad);
for nm = {'adaptive','fixed'}
    d = B.(nm{1}).f_diag;
    fprintf(fid,['    %-8s %d step(s): %d determined, %d undetermined ' ...
        '(%.3f s of %.3f s) | %d zero-length event pair(s) | %d raw wrap ' ...
        'jump(s) | max |d theta| %.4f rad | grid bound >= %.2f Hz | ' ...
        'determined f_9 [%.4f %.4f] Hz\n'],nm{1},d.n_steps,d.n_determined, ...
        d.n_undetermined,d.undetermined_seconds,d.total_seconds, ...
        d.n_zero_length,d.n_raw_wraps,d.max_abs_dtheta_rad, ...
        d.grid_bound_min_Hz,d.f_range_determined(1),d.f_range_determined(2));
end
fprintf(fid,['Y windows are computed over the OPERATING band (run minus [%g %g] s)\n' ...
    '  as the union of BOTH arms with 6 %% headroom, so the two policies share\n' ...
    '  one scale per panel. Panel (d) additionally ignores +/-%g s around each\n' ...
    '  scheduled instant: the first short step after a transaction carries a\n' ...
    '  genuine but very large rate, which would set an axis that flattens the\n' ...
    '  comparison. Anything leaving the window is annotated AT THE FRAME with\n' ...
    '  its peak value; nothing is clipped silently.\n'], ...
    fw(1),fw(2),opts.event_pad);
fprintf(fid,'Event times (CASE_DEFINED, s): %s\n',mat2str(t_events));
fprintf(fid,'Figure: %s\n',png);
fclose(fid);
fprintf('wrote %s\n',prov);

out = struct('png',png,'provenance',prov, ...
    'adaptive_cache',afile,'fixed_cache',xfile, ...
    'adaptive_sha',sha_a,'fixed_sha',sha_x);
end

% ==========================================================================
function b = bus9_signals(r,y9,bus9,determined_rad)
%BUS9_SIGNALS  Bus-9 voltage, shunt power and the bus's OWN frequency.
%
% All four traces come from the accepted trajectory of ONE arm, on that arm's
% own sample grid. Nothing is interpolated onto another grid, decimated or
% filtered.
%
%   Vm  |V_9(t)|                      from bus_voltage_magnitude directly
%   P,Q real/imag of |V_9|^2 * conj(y_9 + 1_fault/Z_f); y_9 is the case-folded
%       load admittance passed in, and the fault term is present exactly on the
%       samples the run labels 'fault' -- the same topology label the integrator
%       used to select Yfault. No load step exists on this schedule, so the live
%       multiplier is 1 everywhere by construction (asserted by the caller).
%   f   f_0 + (1/2pi) d(theta_9)/dt, from the bus's OWN voltage angle. See
%       BUS_FREQUENCY for the frame, wrapping, event-jump and resolution
%       treatment and for the gate on each. Carried on its own time vector t_f,
%       because a secant belongs to the MIDPOINT of the step it spans, not to
%       either endpoint.
t  = r.t(:);
nt = numel(t);
nb = numel(r.bus_ids);
assert(size(r.bus_voltage_magnitude,1)==nb && size(r.bus_voltage_magnitude,2)==nt, ...
    'generate_bus9_adaptive_vs_fixed_160s:voltageShape', ...
    'bus_voltage_magnitude is %s for %d buses over %d samples.', ...
    mat2str(size(r.bus_voltage_magnitude)),nb,nt);
Vm = abs(r.bus_voltage_magnitude(bus9,:)).';

lab = r.topology_history(:);
assert(numel(lab)==nt,'generate_bus9_adaptive_vs_fixed_160s:topologyLength', ...
    'topology_history has %d entries for %d samples.',numel(lab),nt);
in_fault = strcmp(lab,'fault');
assert(any(in_fault),'generate_bus9_adaptive_vs_fixed_160s:noFaultSamples', ...
    'No sample carries the fault topology label; the fault window is missing.');
Zf = r.sched.Zf;
S9t  = (Vm.^2).*conj(y9 + in_fault*(1/Zf));

[fv,tf,fdiag] = bus_frequency(r,bus9,Vm,determined_rad);

b = struct('t',t,'Vm',Vm,'P',real(S9t),'Q',imag(S9t), ...
    't_f',tf,'f',fv,'f_diag',fdiag);
end

% ==========================================================================
function [f,tf,diag] = bus_frequency(r,bus9,Vm_pub,determined_rad)
%BUS_FREQUENCY  The frequency AT one bus, from that bus's own voltage angle.
%
%   f_9(t) = f_0 + (1/2pi) d(theta_9)/dt, as the secant slope of the UNWRAPPED
%   angle across each accepted step, carried at the step's midpoint. Bus 9 has
%   no device, so no frequency is a state there and none is published; this is
%   the only frequency that bus has, and it is derived from a solved algebraic
%   variable of the run rather than from any device's estimate.
%
%   The complex bus voltage is reconstructed from y_traj, whose rows INTERLEAVE
%   the real and imaginary part of each bus voltage. That layout is not assumed:
%   the reconstructed magnitude is checked against the run's own published
%   bus_voltage_magnitude to EXACTLY zero, so a different packing (or a
%   different bus ordering) cannot pass unnoticed.
%
%   Three things are removed rather than divided through:
%     * zero-length steps -- an event publishes a left and a right sample at ONE
%       instant, and a difference across that pair is a jump, not a rate
%     * the wrap -- the angle is unwrapped before differencing
%     * unresolved steps -- a secant can only express an angle motion below pi,
%       so a step whose |d theta| reaches DETERMINED_RAD is returned as NaN and
%       drawn as a gap. How many, and how much time they cover, is reported.
ny = size(r.y_traj,1);
assert(mod(ny,2)==0 && ny/2==numel(r.bus_ids), ...
    'generate_bus9_adaptive_vs_fixed_160s:networkStateShape', ...
    ['y_traj has %d rows for %d buses; the bus voltage layout this figure ' ...
     'reads (two interleaved rows per bus) does not hold.'],ny,numel(r.bus_ids));
V = r.y_traj(1:2:end,:) + 1i*r.y_traj(2:2:end,:);
resid = max(abs(abs(V) - r.bus_voltage_magnitude),[],'all');
assert(resid==0, ...
    'generate_bus9_adaptive_vs_fixed_160s:networkStateLayout', ...
    ['Reconstructing the bus voltages from y_traj does not reproduce the ' ...
     'run''s own bus_voltage_magnitude (max difference %.3e). The rows this ' ...
     'figure reads as bus 9''s real and imaginary part are not that bus''s ' ...
     'voltage, so an angle rate taken from them would not be its ' ...
     'frequency.'],resid);
assert(max(abs(abs(V(bus9,:)).' - Vm_pub))==0, ...
    'generate_bus9_adaptive_vs_fixed_160s:busRowMismatch', ...
    'The reconstructed bus-9 row does not match the published bus-9 magnitude.');

f0 = 60;
if isfield(r,'agsi_reference') && isstruct(r.agsi_reference) && ...
        isfield(r.agsi_reference,'bases') && ...
        isfield(r.agsi_reference.bases,'f0_Hz')
    f0 = double(r.agsi_reference.bases.f0_Hz);
end
assert(isfinite(f0) && f0>0, ...
    'generate_bus9_adaptive_vs_fixed_160s:nominalFrequencyUnrecorded', ...
    'The arm records no usable nominal frequency; f_9 is a deviation from one.');

t   = r.t(:);
th  = unwrap(angle(V(bus9,:)).');
dt  = diff(t);
dth = diff(th);
tf  = (t(1:end-1) + t(2:end))/2;
live = dt > 0;
det  = live & abs(dth) < determined_rad;
f = nan(numel(tf),1);
f(det) = f0 + (dth(det)./dt(det))/(2*pi);

% THE FRAME GATE's raw material: before the first event the system is
% synchronous, so bus 9's angle must be stationary in the run's own frame.
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
diag.pre_event_f_range = finite_range(f(pre));
diag.f_range_determined = finite_range(f(det));
end

% ==========================================================================
function frequency_frame_gate(B,afile,xfile)
%FREQUENCY_FRAME_GATE  An angle rate is a frequency only in a frame rotating at f_0.
%   Before the first event both arms are synchronous, so bus 9's angle must be
%   STATIONARY and f_9 must come out at exactly the nominal. A frame that
%   rotated at anything else -- or a y_traj row that was not this bus -- fails
%   here rather than producing a plausible-looking trace.
FRAME_TOL = 1e-9;
files = struct('adaptive',afile,'fixed',xfile);
for nm = {'adaptive','fixed'}
    d = B.(nm{1}).f_diag;
    assert(d.n_pre_event > 0, ...
        'generate_bus9_adaptive_vs_fixed_160s:noPreEventSamples', ...
        ['Arm %s (%s) has no determined bus-9 frequency sample before its ' ...
         'first event, so the frame the angle rate is measured in cannot be ' ...
         'verified.'],nm{1},files.(nm{1}));
    dev = max(abs(d.pre_event_f_range - d.f0_Hz));
    assert(dev <= FRAME_TOL, ...
        'generate_bus9_adaptive_vs_fixed_160s:frequencyFrameGate', ...
        ['Arm %s (%s): before its first event bus 9''s derived frequency ' ...
         'spans [%.9f %.9f] Hz, %.3e off the nominal %.6f Hz (tolerance ' ...
         '%.1e). The system is synchronous there, so the bus angle must be ' ...
         'stationary in the run''s frame; a nonzero rate means the angle rate ' ...
         'this figure draws is not a frequency in that frame.'], ...
        nm{1},files.(nm{1}),d.pre_event_f_range(1),d.pre_event_f_range(2), ...
        dev,d.f0_Hz,FRAME_TOL);
end
fprintf(['bus-9 frequency frame gate on BOTH arms: f_9 = %.9f Hz before the ' ...
    'first event\n'],B.adaptive.f_diag.f0_Hz);
for nm = {'adaptive','fixed'}
    d = B.(nm{1}).f_diag;
    fprintf(['  %-8s %d of %d step(s) determined (|dtheta| < %.4f rad); %d ' ...
        'undetermined = %.3f s of %.3f s; grid bound %.2f Hz; f_9 ' ...
        '[%.4f %.4f] Hz\n'],nm{1},d.n_determined,d.n_steps,d.determined_rad, ...
        d.n_undetermined,d.undetermined_seconds,d.total_seconds, ...
        d.grid_bound_min_Hz,d.f_range_determined(1),d.f_range_determined(2));
end
end

% ==========================================================================
function r = finite_range(Y)
%FINITE_RANGE  [min max] over the finite samples of a channel, for provenance.
y = Y(:);
y = y(isfinite(y));
if isempty(y), r = [NaN NaN]; else, r = [min(y) max(y)]; end
end

% ==========================================================================
function png = draw_bus9_compare(B,opts,t_events,odir)
%DRAW_BUS9_COMPARE  2x2 comparison at bus 9: adaptive against fixed-GFL.
%
% Bus 9 is the fault bus and carries load but no device, so it reports what
% the island delivers to a load bus rather than what any one controller
% commands. The two arms are drawn on their own sample grids.
%
% LINE-ONLY. No area, fill or patch is drawn under any curve: a thin trace
% must never read as a thick one, which is exactly the confusion an
% oscillation comparison must not create.
fname = 'sg_fault_cycle160_bus9_compare.png';
w = opts.width_in; h = opts.height_in;
f = pf_page_figure(w,h,opts.font_size,'Times New Roman');
tl = tiledlayout(f,2,2,'TileSpacing','compact','Padding','compact');

BLUE = [0.00 0.24 0.75];
GREY = [0.45 0.45 0.45];
A = B.adaptive; F = B.fixed;

% Axis windows are computed from the union of BOTH arms with a fixed 6 %
% headroom, so the two policies share one scale per panel. With the fault
% window excluded the bolted-fault excursion is allowed to leave the axes --
% on V it spans the [0.26 1.86] pu burst against an island band near
% [0.55 1.14] pu, so a window containing it compresses the whole islanded
% comparison. Anything that leaves the window is marked at the frame with its
% peak value, so no reader can mistake a clipped excursion for the data ending.
%
% Panel (d) excludes a further margin around each switching instant: an event
% moves the algebraic state discontinuously, so the first short step after one
% carries a genuine but very large rate (136.72 Hz on the adaptive arm at the
% machine trip) which would flatten the 47..73 Hz comparison the panel is for.
% Its samples sit on t_f, the step midpoints, so its masks are built on t_f.
fw = opts.fault_window;
[kA,exA] = window_mask(A.t,fw,false,opts,t_events);
[kF,exF] = window_mask(F.t,fw,false,opts,t_events);
[kAf,exAf] = window_mask(A.t_f,fw,true,opts,t_events);
[kFf,exFf] = window_mask(F.t_f,fw,true,opts,t_events);
ylP = span_limits(pk(A,'P',kA),pk(F,'P',kF));
ylQ = span_limits(pk(A,'Q',kA),pk(F,'Q',kF));
ylV = span_limits(pk(A,'Vm',kA),pk(F,'Vm',kF));
% The 60 Hz nominal is a rule this panel draws, so the window is computed to
% contain it rather than hoped to: a reference the reader cannot see is worse
% than none.
ylF = span_limits(pk(A,'f',kAf),pk(F,'f',kFf),A.f_diag.f0_Hz);

% (a) active power ---------------------------------------------------------
ax = nexttile(tl); hold(ax,'on');
hF = plot(ax,F.t,F.P,'Color',GREY,'LineWidth',0.8);
hA = plot(ax,A.t,A.P,'Color',BLUE,'LineWidth',1.1);
finish_panel(ax,opts,t_events,ylP,'$P_{\mathrm{Bus9}}$ [p.u.]','','(a)', ...
    [exA; exF]);
mark_offscale(ax,A.t,A.P,ylP,BLUE,'%.2f');
mark_offscale(ax,F.t,F.P,ylP,GREY,'%.2f');

% (b) reactive power --------------------------------------------------------
ax = nexttile(tl); hold(ax,'on');
plot(ax,F.t,F.Q,'Color',GREY,'LineWidth',0.8);
plot(ax,A.t,A.Q,'Color',BLUE,'LineWidth',1.1);
finish_panel(ax,opts,t_events,ylQ,'$Q_{\mathrm{Bus9}}$ [p.u.]','','(b)', ...
    [exA; exF]);
mark_offscale(ax,A.t,A.Q,ylQ,BLUE,'%.2f');
mark_offscale(ax,F.t,F.Q,ylQ,GREY,'%.2f');

% (c) voltage magnitude -----------------------------------------------------
ax = nexttile(tl); hold(ax,'on');
plot(ax,F.t,F.Vm,'Color',GREY,'LineWidth',0.8);
plot(ax,A.t,A.Vm,'Color',BLUE,'LineWidth',1.1);
finish_panel(ax,opts,t_events,ylV,'$V_{\mathrm{Bus9}}$ [p.u.]','$t$ [s]','(c)', ...
    [exA; exF]);
mark_offscale(ax,A.t,A.Vm,ylV,BLUE,'%.2f');
mark_offscale(ax,F.t,F.Vm,ylV,GREY,'%.2f');

% (d) the frequency at bus 9 itself -----------------------------------------
% Derived from this bus's own voltage angle on BOTH arms, so the panel is a
% comparison: f_9 = f_0 + (1/2pi) d(theta_9)/dt, at the midpoint of each
% accepted step, hence drawn against t_f rather than t. The grey trace is
% BROKEN, not absent -- it is drawn where the fixed arm's own 20 ms output grid
% resolves the rate and gapped where it does not, and the gaps are themselves a
% finding: a locked-GFL fleet moves this bus's angle faster than the run
% recorded it. Nothing is substituted to keep either trace continuous.
ax = nexttile(tl); hold(ax,'on');
plot(ax,F.t_f,F.f,'Color',GREY,'LineWidth',0.8);
plot(ax,A.t_f,A.f,'Color',BLUE,'LineWidth',1.0);
yline(ax,A.f_diag.f0_Hz,'-','Color',[0.30 0.30 0.30],'LineWidth',0.5, ...
    'HandleVisibility','off','Interpreter','latex');
finish_panel(ax,opts,t_events,ylF,'$f_{\mathrm{Bus9}}$ [Hz]','$t$ [s]','(d)', ...
    [exAf; exFf]);
mark_offscale(ax,A.t_f,A.f,ylF,BLUE,'%.2f');
mark_offscale(ax,F.t_f,F.f,ylF,GREY,'%.2f');

% Legend built from EXPLICIT handles: each policy's series carries several
% lines across the four panels, so relying on HandleVisibility would let the
% legend pick the wrong one.
lg = legend([hA(1) hF(1)],{'\textit{Adaptive GFL/GFM}','\textit{Fixed GFL}'}, ...
    'Interpreter','latex','Orientation','horizontal','Box','off');
lg.Layout.Tile = 'north';
assert(numel(lg.String)==2, ...
    'generate_bus9_adaptive_vs_fixed_160s:legendEntries', ...
    'The comparison legend must carry exactly two policy entries.');
audit_latex(f);
png = fullfile(odir,fname);
pf_page_export(f,png,opts.dpi,opts.save_fig);
end

% ==========================================================================
function [keep,excl] = window_mask(t,fw,pad_events,opts,t_events)
%WINDOW_MASK  Which samples of one arm SET a panel's y window.
% Never which samples are DRAWN -- every sample is drawn. KEEP selects what the
% window is computed over; EXCL is the complementary set of time intervals,
% which finish_panel then allows an excursion inside, because mark_offscale
% annotates whatever leaves.
%
% The fault window always comes out: a bolted fault drives every channel far
% past its operating band. PAD_EVENTS additionally removes a margin around each
% switching instant, which the frequency panel needs and the others do not -- an
% algebraic state jumps at a transaction, so the first short step after one
% carries a very large but entirely genuine rate.
t = t(:);
excl = [fw(1) fw(2)];
keep = ~(t >= fw(1) & t <= fw(2));
if pad_events
    for e = t_events
        a = e - opts.event_pad; b = e + opts.event_pad;
        keep = keep & ~(t >= a & t <= b);
        excl = [excl; a b]; %#ok<AGROW>
    end
end
end

% ==========================================================================
function v = pk(S,ch,keep)
%PK  The samples of one channel that set a panel's y window.
% No *_plot layer exists on this figure: the window contains the drawn
% simulation samples, restricted to the samples `keep' selects (the fault
% excursion is excluded by the caller).
v = S.(ch);
if isvector(v), v = v(:); end
keep = keep(:);
v = v(keep,:);
end

% ==========================================================================
function yl = span_limits(varargin)
%SPAN_LIMITS  A shared y window covering every finite sample of every series
% given, with 6 % headroom on each side.  Used so both compared policies read
% on one scale.  This sets the VIEW; no data is modified or clipped, and
% finish_panel asserts afterwards that nothing falls outside the window.
% A scalar argument may be passed to force a reference level (the frequency
% panel's nominal) inside the window.
v = [];
for k = 1:numel(varargin)
    s = varargin{k}(:);
    v = [v; s(isfinite(s))]; %#ok<AGROW>
end
assert(~isempty(v),'generate_bus9_adaptive_vs_fixed_160s:emptySeries', ...
    'A panel was asked for limits over no finite samples.');
lo = min(v); hi = max(v);
pad = 0.06*(hi-lo);
if pad <= 0, pad = max(0.01,0.06*abs(hi)); end
yl = [lo-pad hi+pad];
% A magnitude that never goes negative should not be given a negative axis:
% the headroom below zero would suggest a sign the quantity cannot take.
if lo >= 0 && yl(1) < 0, yl(1) = 0; end
end

% ==========================================================================
function mark_offscale(ax,t,Y,yl,col,fmt)
%MARK_OFFSCALE  Flag data that leaves the panel window, with its peak value.
% A view that silently cut an excursion would misrepresent the run, so every
% channel that exits the window gets an arrow at the frame carrying the peak.
% The arrow is drawn from the SIMULATION channel, so the annotated number is a
% solver value. Y may carry several channels (panel (d)); the extreme over all
% of them is annotated once, at its own sample.
t = t(:);
[hi,ih] = max(Y,[],1);
[lo,il] = min(Y,[],1);
[hi,c_hi] = max(hi); ih = ih(c_hi);
[lo,c_lo] = min(lo); il = il(c_lo);
if hi > yl(2)
    text(ax,t(ih),yl(2),sprintf('$\\uparrow$ %s',sprintf(fmt,hi)), ...
        'Interpreter','latex','Color',col,'FontSize',9, ...
        'HorizontalAlignment','center','VerticalAlignment','top', ...
        'BackgroundColor','w','Margin',0.5);
end
if lo < yl(1)
    text(ax,t(il),yl(1),sprintf('$\\downarrow$ %s',sprintf(fmt,lo)), ...
        'Interpreter','latex','Color',col,'FontSize',9, ...
        'HorizontalAlignment','center','VerticalAlignment','bottom', ...
        'BackgroundColor','w','Margin',0.5);
end
end

% ==========================================================================
function finish_panel(ax,opts,t_events,ylim_pair,ylab,xlab,tag,excl)
%FINISH_PANEL  Shared axis dressing: event marks, LaTeX labels, no box.
% The corner tag replaces an in-figure title, so the caption carries the
% description and the artwork carries no prose.  The window must contain every
% plotted sample EXCEPT inside the declared intervals EXCL -- the fault window
% on every panel, and on the frequency panel a margin around each switching
% instant -- where the excursion is deliberately allowed to leave the axes and
% is annotated at the frame with its peak value.  A sample that left the window
% anywhere else would be silently hidden, which would misrepresent the
% comparison, so that still aborts.
if nargin < 8 || isempty(excl)
    excl = opts.fault_window;
end
for e = t_events
    xline(ax,e,':','Color',[0.55 0.55 0.55],'LineWidth',0.6, ...
        'HandleVisibility','off','Interpreter','latex');
end
ylabel(ax,ylab,'Interpreter','latex');
if ~isempty(xlab)
    xlabel(ax,xlab,'Interpreter','latex');
else
    set(ax,'XTickLabel',[]);
end
if ~isempty(ylim_pair)
    ylim(ax,ylim_pair);
    lines = findobj(ax,'Type','line');
    for k = 1:numel(lines)
        yd = lines(k).YData(:);
        xd = lines(k).XData(:);
        keep = true(size(yd));
        if numel(xd) == numel(yd)
            for j = 1:size(excl,1)
                keep = keep & ~(xd >= excl(j,1) & xd <= excl(j,2));
            end
        end
        yd = yd(keep);
        yd = yd(isfinite(yd));
        if isempty(yd), continue; end
        assert(min(yd)>=ylim_pair(1)-1e-9 && max(yd)<=ylim_pair(2)+1e-9, ...
            'generate_bus9_adaptive_vs_fixed_160s:clippedSeries', ...
            ['Outside the declared interval(s) %s a plotted series spans ' ...
             '[%.6f %.6f], beyond the panel window [%.6f %.6f]; the view ' ...
             'would hide samples without annotating them.'], ...
            mat2str(excl,6),min(yd),max(yd),ylim_pair(1),ylim_pair(2));
    end
end
set(ax,'xlim',[0 160],'Box','off','TickDir','out','Layer','bottom', ...
    'XMinorGrid','on','YMinorGrid','on','MinorGridLineStyle','--', ...
    'MinorGridColor',[0.65 0.65 0.65],'GridLineStyle','--', ...
    'GridColor',[0.85 0.85 0.85],'TickLabelInterpreter','latex', ...
    'FontName','Times New Roman','FontSize',opts.font_size);
grid(ax,'on');
text(ax,0.975,0.075,tag,'Units','normalized','Interpreter','latex', ...
    'HorizontalAlignment','right','VerticalAlignment','bottom', ...
    'FontName','Times New Roman','FontSize',opts.font_size, ...
    'BackgroundColor','w','EdgeColor',[0.35 0.35 0.35],'Margin',2);
end

% ==========================================================================
function audit_latex(f)
%AUDIT_LATEX  Enforce then verify the lettering contract of this figure: every
% text-bearing object must render through the LaTeX interpreter, tick labels
% included.  tiledlayout and legend rewrite interpreters after creation, so
% the object tree is walked and pinned once, then re-read to verify.  This
% pins the INTERPRETER, never a value.
for prop = {'Interpreter','TickLabelInterpreter'}
    objs = findall(f,'-property',prop{1});
    for k = 1:numel(objs)
        if ~strcmpi(objs(k).(prop{1}),'latex')
            objs(k).(prop{1}) = 'latex';
        end
    end
end
bad = {};
for prop = {'Interpreter','TickLabelInterpreter'}
    objs = findall(f,'-property',prop{1});
    for k = 1:numel(objs)
        if ~strcmpi(objs(k).(prop{1}),'latex')
            bad{end+1} = sprintf('%s.%s = "%s"', ...
                class(objs(k)),prop{1},objs(k).(prop{1})); %#ok<AGROW>
        end
    end
end
assert(isempty(bad),'generate_bus9_adaptive_vs_fixed_160s:latexAudit', ...
    'Lettering audit failed; these objects do not use the LaTeX interpreter:\n  %s', ...
    strjoin(bad,'\n  '));
% No axis may draw a box: the report style is left and bottom rules only.
axl = findall(f,'Type','axes');
for k = 1:numel(axl)
    assert(strcmpi(axl(k).Box,'off'), ...
        'generate_bus9_adaptive_vs_fixed_160s:boxAudit', ...
        'An axis still draws a box; the report style forbids it.');
end
end

% ==========================================================================
function t_events = schedule_times(r)
%SCHEDULE_TIMES  The four CASE_DEFINED disturbance times of one arm.
% The sg_fault_cycle profile arms exactly these four instants
% (sg_trip < fault_on < fault_clear < sg_on <= t_end); there is no load step,
% no line trip and no restore_time on this schedule by design.
names = {'sg_trip','fault_on','fault_clear','sg_on'};
t_events = zeros(1,numel(names));
for k = 1:numel(names)
    assert(isfield(r.sched,names{k}) && isscalar(r.sched.(names{k})) && ...
        isfinite(r.sched.(names{k})), ...
        'generate_bus9_adaptive_vs_fixed_160s:missingSchedule', ...
        'The arm schedule lacks a finite scalar %s.',names{k});
    t_events(k) = double(r.sched.(names{k}));
end
end

% ==========================================================================
function [value,sha] = load_guarded(file,field)
%LOAD_GUARDED  Load a cache, refusing a read that races a concurrent writer.
% field='' returns the whole struct.
sha = sha256_of(file);
S = load(file);
assert(strcmp(sha,sha256_of(file)), ...
    'generate_bus9_adaptive_vs_fixed_160s:cacheChangedWhileReading', ...
    'Cache %s changed during the read; a concurrent writer is active.',file);
if isempty(field)
    value = S;
else
    assert(isfield(S,field),'generate_bus9_adaptive_vs_fixed_160s:cacheSchema', ...
        'Cache %s carries no field "%s".',file,field);
    value = S.(field);
end
end

% ==========================================================================
function sha = sha256_of(f)
%SHA256_OF  Hex SHA-256 of a file via Java, on an absolute path.
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
sha = sprintf('%02x', reshape(typecast(h.digest(),'uint8'),1,[]));
end
