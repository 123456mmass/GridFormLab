function manifest = generate_ne39_5sg5ibr_fault_load_report_data(evidence_folder)
%GENERATE_NE39_5SG5IBR_FAULT_LOAD_REPORT_DATA  Reproducible report evidence.
%   Loads a completed NE39 5SG+5IBR fault+load-study artifact folder's raw.mat
%   ONCE (request + result) and exports the IEEE14-style CSV evidence set used
%   by report_ne39_5sg5ibr_fault_load_en.tex:
%
%     case_bus_data.csv, case_line_data.csv   -- case inputs
%     normal_pf_bus.csv                        -- solved equilibrium bus voltages
%     normal_pf_power.csv                      -- bus generation / load / net
%     normal_pf_line_flow.csv                  -- branch sending-end flows + losses
%     normal_resource_pf.csv                   -- per-device injections (initial config)
%     mode_level_timeline.csv                  -- VF level per device per (decimated) sample
%     ts_bus_vmin_vmax.csv                     -- envelope of bus voltage magnitudes
%     ts_device_frequency.csv                  -- per-device frequency (Hz)
%     ts_device_power.csv                      -- per-device P / Q (MW / MVAr)
%     ts_device_current.csv                    -- per-device current magnitude (pu sys)
%     ts_device_dq_currents.csv                -- converter i_d / i_q states (device MVA base)
%     ts_sg_frequency.csv                      -- per-SG rotor frequency from each omega state
%     scr_diagnostic.csv                       -- ASSUMED_DIAGNOSTIC grid-strength SCR per IBR
%     ts_coi_frequency.csv                     -- COI frequency (Hz)
%     ts_dt_history.csv                        -- accepted step size history
%     event_marks.csv                          -- applied event transaction times
%     manifest.txt                             -- provenance
%
%   This script reads the stored run and computes nothing beyond presentation
%   arithmetic (decimation, unit scaling, branch-power algebra from the same
%   stored voltages).  It runs no simulation, changes no gate, and touches no
%   raw.mat.  SG frequency comes from the x_traj omega state of each two-state
%   classical plant (f_Hz = f0*omega); each of the FIVE SG columns is the plant's
%   own absolute rotor speed, read unchanged from the stored trajectory.
%
%   Usage:
%     generate_ne39_5sg5ibr_fault_load_report_data( ...
%       'D:\4-year-project\GridFormLab\output\diagnostics\ne39_5sg5ibr_fault_load_study_<ts>')

if nargin < 1 || isempty(evidence_folder)
    error('ne39:report:folderRequired', ...
        'Pass the study artifact folder containing raw.mat.');
end
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
out = fullfile(root,'docs','source','figures','ne39_5sg5ibr_fault_load');
if ~isfolder(out), mkdir(out); end

raw_file = fullfile(evidence_folder,'raw.mat');
assert(isfile(raw_file),'ne39:report:missingRaw','No raw.mat in %s',evidence_folder);
fprintf('loading %s (%.1f MB); single slow step by construction ...\n', ...
    raw_file,dir(raw_file).bytes/1e6);
t0 = tic;
S = load(raw_file,'request','result','elapsed');
fprintf('  loaded in %.1f s\n',toc(t0));
r = S.result; c = S.request.case_data; nt = numel(r.t);

% ---- Case input tables ------------------------------------------------------
% Column meanings follow the project case layout (case_ne39_tamu_mixed): bus_data
% col3=Vm, col4=Va, col5=Pg pu, col6=Qg pu, col7-10 = raw Pd/Qd/Gs/Bs per unit.
% The load schedules live at columns 7-8 (times S for MW), NOT at mpc.bus
% columns 3-4 (which are the raw TAMU Pd/Qd MW).  Shunts come from columns 9-10.
bus = c.bus_data; base = c.base_values.S_base_MVA; nb = size(bus,1);
role = repmat("PQ",nb,1);
role(c.sg_buses) = "PV"; role(c.sg_buses(1)) = "SLACK";
role(c.ibr_buses) = "GFL";
t = table(bus(:,1),role,bus(:,7),bus(:,8),bus(:,9),bus(:,10), ...
    'VariableNames',{'bus_id','type','Pd_pu','Qd_pu','Gs_pu','Bs_pu'});
writetable(t,fullfile(out,'case_bus_data.csv'));

l = c.mpc.branch;
t = table((1:size(l,1)).',l(:,1),l(:,2),l(:,3),l(:,4),l(:,5), ...
    'VariableNames',{'branch_index','from_bus','to_bus','r_pu','x_pu','b_pu'});
writetable(t,fullfile(out,'case_line_data.csv'));

% ---- Solved equilibrium bus voltages (y0 of the stored initial equilibrium) --
V = complex(r.equilibrium.y0(1:2:end),r.equilibrium.y0(2:2:end));
assert(numel(V)==nb,'ne39:report:busCount', ...
    'equilibrium y0 has %d complex voltages but mpc has %d buses.',numel(V),nb);
bus_ids = c.mpc.bus(:,1);
% No kV column: the TAMU source leaves bus base kV unspecified, so inventing a
% 69-kV reporting base would be a fabrication.
t = table(bus_ids(:),real(V),imag(V),abs(V),rad2deg(angle(V)), ...
    'VariableNames',{'bus_id','Vx_pu','Vy_pu','V_pu','angle_deg'});
writetable(t,fullfile(out,'normal_pf_bus.csv'));

% ---- Device injections at the solved equilibrium (current_injection ABI) ----
devs = r.equilibrium.devices;
nd = numel(devs);
res = repmat(struct('device_index',0,'device_id','', ...
    'bus_id',0,'mode','', 'P_pu',0,'Q_pu',0,'P_MW',0,'Q_MVAr',0,'V_pu',0),nd,1);
% Use the recorded offsets when present; otherwise fall back to pack order.
if isfield(r.equilibrium,'device_offsets')
    dev_offsets = r.equilibrium.device_offsets(:).';
else
    dev_offsets = [0 cumsum([devs.nx])]; %#ok<AGROW>
end
if isfield(r.equilibrium,'u_offsets')
    u_offsets = r.equilibrium.u_offsets(:).';
else
    u_offsets = [0 cumsum([devs.nu])]; %#ok<AGROW>
end
for k = 1:nd
    d = devs(k);
    xr = dev_offsets(k)+1 : dev_offsets(k)+d.nx;
    if d.nu == 0, u_dev = [];
    else, ur = u_offsets(k)+1 : u_offsets(k)+d.nu; u_dev = r.equilibrium.u_eq(ur);
    end
    I = d.current_injection(0,r.equilibrium.x0(xr),r.equilibrium.y0,u_dev, ...
        r.equilibrium.equilibrium_context);
    vb = V(d.bus_position);
    Sd = vb*conj(I);
    res(k).device_index = k; res(k).device_id = char(d.device_id);
    res(k).bus_id = d.bus_id; res(k).mode = upper(string(d.mode));
    res(k).P_pu = real(Sd); res(k).Q_pu = imag(Sd);
    res(k).P_MW = base*real(Sd); res(k).Q_MVAr = base*imag(Sd);
    res(k).V_pu = abs(vb);
end
t = struct2table(res);
writetable(t,fullfile(out,'normal_resource_pf.csv'));

% ---- Bus generation / load / net injection at the equilibrium ---------------
Sgen = complex(zeros(nb,1));
for k = 1:nd
    bp = find(bus_ids==res(k).bus_id,1);
    Sgen(bp) = Sgen(bp) + res(k).P_pu + 1i*res(k).Q_pu;
end
% Loads: the production contract (composite_dae.build_ybus_local) folds the
% load as a CONSTANT-ADMITTANCE term Yload = conj(S0)./|V0_pf|^2 from the PF
% seed, so the equilibrium consumption is V . conj(Yload . V) at the solved
% voltage -- not the raw MW schedule.  S0 comes from case columns 7-8.
V0pf = c.mpc.bus(:,8).*exp(1i*deg2rad(c.mpc.bus(:,9)));
S0 = (bus(:,7)+1i*bus(:,8));
Yload = conj(S0)./(abs(V0pf).^2+eps);
Sload = V.*conj(Yload.*V);
Sshunt = (bus(:,9)+1i*bus(:,10)).*(abs(V).^2);
t = table(bus_ids(:),real(Sgen),imag(Sgen),real(Sload),imag(Sload), ...
    imag(Sshunt),real(Sgen-Sload),imag(Sgen)+imag(Sshunt)-imag(Sload), ...
    'VariableNames',{'bus_id','P_gen_pu','Q_gen_pu','P_load_pu', ...
    'Q_load_pu','Q_shunt_pu','P_net_pu','Q_net_pu'});
writetable(t,fullfile(out,'normal_pf_power.csv'));

% Branch terminal power from the same stored voltages (PSSE layout
% [from,to,r,x,b_total,tap,shift]; charging divides b_total/2 per terminal).
[Sf,St] = branch_terminal_power_psse(c.mpc.branch,V,bus_ids);
t = table((1:size(c.mpc.branch,1)).',c.mpc.branch(:,1),c.mpc.branch(:,2), ...
    real(Sf),imag(Sf),real(Sf+St),imag(Sf+St), ...
    'VariableNames',{'line','from_bus','to_bus','P_from_pu','Q_from_pu', ...
    'P_loss_pu','Q_loss_pu'});
writetable(t,fullfile(out,'normal_pf_line_flow.csv'));
balance = sum(Sgen) + sum(Sshunt) - sum(Sload) - sum(Sf+St);
fprintf(['equilibrium report balance = %.3e pu ' ...
    '(gens+shunts - loads - losses; shunts = charging + fixed port reactors)\n'], ...
    abs(balance));

% ---- Device per-sample TS traces (all 10 devices) ---------------------------
ids = cellstr(string(r.device_ids)); nds = numel(ids);
bi = zeros(nds,1);
for k = 1:nds, bi(k) = find(bus_ids==r.device_bus_ids(k),1); end
tcol = r.t(:);

t = table(tcol,'VariableNames',{'time_s'});
for k = 1:nds
    t.([matlab.lang.makeValidName(ids{k}) '_V_pu']) = ...
        r.bus_voltage_magnitude(bi(k),:).';
end
writetable(t,fullfile(out,'ts_bus_voltages_devices.csv'));

t = table(tcol,'VariableNames',{'time_s'});
for k = 1:nds
    t.([matlab.lang.makeValidName(ids{k}) '_f_Hz']) = r.device_frequency_Hz(k,:).';
end
writetable(t,fullfile(out,'ts_device_frequency.csv'));

t = table(tcol,'VariableNames',{'time_s'});
for k = 1:nds
    t.([matlab.lang.makeValidName(ids{k}) '_P_MW']) = r.device_P_MW(k,:).';
    t.([matlab.lang.makeValidName(ids{k}) '_Q_MVAr']) = r.device_Q_MVAr(k,:).';
end
writetable(t,fullfile(out,'ts_device_power.csv'));

t = table(tcol,'VariableNames',{'time_s'});
for k = 1:nds
    t.([matlab.lang.makeValidName(ids{k}) '_I_pu']) = ...
        r.device_current_magnitude(k,:).';
end
writetable(t,fullfile(out,'ts_device_current.csv'));

if isfield(r,'coi_frequency_Hz')
    t = table(tcol,r.coi_frequency_Hz(:), ...
        'VariableNames',{'time_s','coi_frequency_Hz'});
    writetable(t,fullfile(out,'ts_coi_frequency.csv'));
end

% ---- Converter dq-frame current states (i_d, i_q of the dual-mode plant) ----
% The dual-mode superset stores [i_d i_q V_dc ...] at slots 1..3 of every 17-
% state IBR block (5 x 17 = 85 converter states, 7 + 85 = 92 total with the
% five two-state classical plants).  i_dq is exported on the device base
% exactly as the plant defines it; the series is NOT rescaled or reconciled.
if isfield(r.equilibrium,'device_offsets')
    dev_offsets = r.equilibrium.device_offsets(:).';
else
    dev_offsets = [0 cumsum([r.equilibrium.devices.nx])];
end
t = table(tcol,'VariableNames',{'time_s'});
k_dev = 0;
for k = 1:nds
    d = r.equilibrium.devices(k);
    if d.nx < 11, continue; end   % 17-state dual blocks only (each SG has 2)
    k_dev = k_dev + 1;
    od = dev_offsets(k);
    t.([matlab.lang.makeValidName(ids{k}) '_id_pu']) = r.x_traj(od+1,:).';
    t.([matlab.lang.makeValidName(ids{k}) '_iq_pu']) = r.x_traj(od+2,:).';
end
writetable(t,fullfile(out,'ts_device_dq_currents.csv'));
fprintf('  dq export: %d 17-state converter blocks (of %d devices)\n',k_dev,nds);

% ---- Per-SG rotor frequency from each plant's own omega state (superset 2) --
% Each classical plant's omega is an ABSOLUTE pu speed (1.0 at nominal) and a
% genuine RHS state stored in x_traj; f_Hz = f0*omega is the same convention
% the harness applies to voltage-forming devices.
f0 = double(c.base_values.frequency_Hz);
t = table(tcol,'VariableNames',{'time_s'});
for k = 1:nds
    d = r.equilibrium.devices(k);
    if d.nx ~= 2, continue; end   % two-state classical plants only
    od = dev_offsets(k);
    omega_k = r.x_traj(od+2,:).';
    t.([matlab.lang.makeValidName(ids{k}) '_omega_pu']) = omega_k;
    t.([matlab.lang.makeValidName(ids{k}) '_f_Hz']) = f0*omega_k;
end
writetable(t,fullfile(out,'ts_sg_frequency.csv'));

t = table(tcol,min(r.bus_voltage_magnitude,[],1).',max(r.bus_voltage_magnitude,[],1).', ...
    'VariableNames',{'time_s','v_min_pu','v_max_pu'});
writetable(t,fullfile(out,'ts_bus_vmin_vmax.csv'));

if isfield(r,'dt_history') && isfield(r,'lte_history')
    n_dt = min(numel(r.dt_history),numel(r.lte_history));
    t = table(r.dt_history(1:n_dt),r.lte_history(1:n_dt), ...
        'VariableNames',{'dt_s','lte'});
    writetable(t,fullfile(out,'ts_dt_history.csv'));
end

% ---- Mode-level timeline (0 open / 1 GFL / 2 VF), decimated to ~4000 rows ----
mh = r.device_modes_history; on = r.device_online_history;
step = max(1,ceil(nt/4000));
keep = 1:step:nt;
if keep(end)~=nt, keep(end+1) = nt; end %#ok<AGROW>
lvl = zeros(nds,numel(keep));
for a = 1:numel(keep)
    j = keep(a);
    for k = 1:nds
        lvl(k,a) = mode_level(mh{k,j},on(k,j));
    end
end
t = table(tcol(keep),'VariableNames',{'time_s'});
for k = 1:nds
    t.([matlab.lang.makeValidName(ids{k}) '_level']) = lvl(k,:).';
end
writetable(t,fullfile(out,'mode_level_timeline.csv'));

% ---- Applied event marks ----------------------------------------------------
ev = r.event_log; rows = {};
for k = 1:numel(ev)
    e = ev(k);
    rows(end+1,:) = {char(string(e.type)),e.t,logical(e.applied), ...
        e.pre_kcl_norm,e.right_kcl_norm}; %#ok<AGROW>
end
t = cell2table(rows,'VariableNames',{'event_type','t_s','applied', ...
    'pre_kcl_norm','right_kcl_norm'});
writetable(t,fullfile(out,'event_marks.csv'));

% ---- ASSUMED_DIAGNOSTIC grid-strength SCR per IBR bus -----------------------
% SCR_i = |V_i|^2 / (|Z_th,ii| * S_rated,i) at the accepted equilibrium.  Z_th
% is the passive-network Thevenin at bus i: a column solve of the pre-fault
% admittance rebuilt from the stored case inputs.  S_rated is the composition's
% PROJECT_DERIVED converter rating.  This column is a physical grid-strength
% diagnostic only and never a gate outcome.
rating_map = containers.Map(num2cell(c.ibr_buses(:)),num2cell(c.ibr_ratings_MVA(:)));
Yscr = sparse(nb,nb);
br = c.mpc.branch;
for k2 = 1:size(br,1)
    i2 = find(bus_ids==br(k2,1),1); j2 = find(bus_ids==br(k2,2),1);
    tap2 = br(k2,6); if tap2==0, tap2=1; end
    a2 = tap2*exp(1i*deg2rad(br(k2,7)));
    ys2 = 1/(br(k2,3)+1i*br(k2,4)); ysh2 = 1i*br(k2,5)/2;
    Yscr(i2,i2) = Yscr(i2,i2) + (ys2+ysh2)/(a2*conj(a2));
    Yscr(i2,j2) = Yscr(i2,j2) - ys2/conj(a2);
    Yscr(j2,i2) = Yscr(j2,i2) - ys2/a2;
    Yscr(j2,j2) = Yscr(j2,j2) + ys2 + ysh2;
end
Yscr = Yscr + spdiags((bus(:,9)+1i*bus(:,10)) + Yload,0,nb,nb);
rows_ibr = find(isKey(rating_map,num2cell(bus_ids(:)))).';
nIBR = numel(rows_ibr);
Zth_diag = zeros(nIBR,1); ssc_diag = zeros(nIBR,1); scr_diag = nan(nIBR,1);
rate_diag = zeros(nIBR,1);
for k2 = 1:nIBR
    e = zeros(nb,1); e(rows_ibr(k2)) = 1;
    vz = full(Yscr\e);
    if ~all(isfinite(vz)), continue; end
    Zth_diag(k2) = abs(vz(rows_ibr(k2)));
    ssc_diag(k2) = abs(V(rows_ibr(k2)))^2/Zth_diag(k2)*base;
    rate_diag(k2) = rating_map(bus_ids(rows_ibr(k2)));
    scr_diag(k2) = ssc_diag(k2)/rate_diag(k2);
end
t = table(bus_ids(rows_ibr(:)),Zth_diag,ssc_diag,rate_diag,scr_diag, ...
    'VariableNames',{'bus_id','abs_Zth_pu','Ssc_MVA','rating_MVA','SCR'});
writetable(t,fullfile(out,'scr_diagnostic.csv'));
fprintf('  SCR diagnostic (ASSUMED_DIAGNOSTIC): Zth rebuilt from the stored case, SCR = Ssc/rating\n');

% ---- Mode / horizon scalars for the report prose ----------------------------
scalars = struct();
scalars.initial_gfm_count = sum(strcmpi(string(mh(:,1)),'gfm'));
scalars.final_gfm_count = sum(strcmpi(string(mh(:,end)),'gfm'));
scalars.final_sg_count = sum(strcmpi(string(mh(:,end)),'synchronous'));
scalars.reclose_status = 'NOT_REQUESTED';
scalars.horizon_reached_s = r.t(end);
scalars.accepted_samples = nt;
if isfield(r,'rejected_steps'), scalars.rejected_steps = r.rejected_steps; end
if isfield(r,'stepper'), scalars.stepper = char(string(r.stepper)); end
scalars.production_certified = false;
scalars.equilibrium_converged = logical(r.equilibrium.converged);
if isfield(r,'ne39_assessment') && isstruct(r.ne39_assessment)
    scalars.energy_error_pu_s = r.ne39_assessment.energy_error_pu_s;
    scalars.voltage_excursion_samples = r.ne39_assessment.voltage_excursion_samples;
    scalars.assessment_samples_checked = r.ne39_assessment.samples_checked;
    scalars.strict_snapshot_failures = r.ne39_assessment.strict_snapshot_failures;
end

% ---- Manifest ---------------------------------------------------------------
manifest = struct('generated_at',char(datetime('now','Format','yyyy-MM-dd HH:mm:ss Z')), ...
    'branch',git_text(root,'rev-parse --abbrev-ref HEAD'), ...
    'commit',git_text(root,'rev-parse HEAD'), ...
    'case_id','ne39_5sg_5ibr','model_inventory','tamu_mixed_sg_ibr', ...
    'evidence_folder',evidence_folder, ...
    'raw_mat_bytes',dir(raw_file).bytes, ...
    'classification',char(string(r.classification)), ...
    'production_certified',false, ...
    'chronology','fault_load_step_no_sg_trip', ...
    'horizon_reached_s',scalars.horizon_reached_s, ...
    'accepted_samples',scalars.accepted_samples, ...
    'stepper',getfield_default(scalars,'stepper','UNKNOWN'), ...
    'rejected_steps',getfield_default(scalars,'rejected_steps',NaN), ...
    'initial_gfm_count',scalars.initial_gfm_count, ...
    'final_gfm_count',scalars.final_gfm_count, ...
    'final_sg_count',scalars.final_sg_count, ...
    'equilibrium_converged',scalars.equilibrium_converged, ...
    'equilibrium_balance_pu',abs(balance), ...
    'reported_power_balance_pu',abs(balance), ...
    'energy_error_pu_s',scalars.energy_error_pu_s, ...
    'mode_decimation_step',step, ...
    'output_directory',out);
save(fullfile(out,'report_evidence.mat'),'manifest','-v7.3');
write_manifest(manifest,fullfile(out,'manifest.txt'));
fprintf('NE39 report evidence written to %s\ninitial_gfm=%d final_gfm=%d horizon=%.4f\n', ...
    out,scalars.initial_gfm_count,scalars.final_gfm_count,scalars.horizon_reached_s);
end

% ========================================================================
function v = getfield_default(s,f,d)
if isfield(s,f), v = s.(f); else, v = d; end
end

function L = mode_level(m,online)
% 0 = breaker open, 1 = grid-following, 2 = voltage-forming (GFM or SG).
if ~islogical(online), online = logical(online); end
if ~online, L = 0; return; end
s = lower(char(string(m)));
if contains(s,'open'),    L = 0;
elseif strcmp(s,'gfl'),   L = 1;
else,                     L = 2;
end
end

function [Sf,St] = branch_terminal_power_psse(br,V,bus_ids)
% PSSE-branch layout straight from ne39_tamu_raw: columns
% [from,to,r,x,b_total,tap_ratio,shift_deg]. Charging divides equally as the
% production Ybus builder stamps it (b_total/2 per terminal).
nl = size(br,1); Sf = complex(zeros(nl,1)); St = Sf;
for k = 1:nl
    i = find(bus_ids==br(k,1),1); j = find(bus_ids==br(k,2),1);
    tap = br(k,6); if tap==0, tap = 1; end
    a = tap*exp(1i*deg2rad(br(k,7)));
    ys = 1/(br(k,3)+1i*br(k,4)); ysh = 1i*br(k,5)/2;
    If = ((ys+ysh)/(a*conj(a)))*V(i) - (ys/conj(a))*V(j);
    It = (ys+ysh)*V(j) - (ys/a)*V(i);
    Sf(k) = V(i)*conj(If); St(k) = V(j)*conj(It);
end
end

function s = git_text(root,args)
[status,s] = system(sprintf('git -C "%s" %s',root,args));
if status~=0, s = 'UNAVAILABLE'; else, s = strtrim(s); end
end

function write_manifest(m,file)
fid = fopen(file,'w'); c = onCleanup(@() fclose(fid)); %#ok<NASGU>
f = fieldnames(m);
for k = 1:numel(f)
    v = m.(f{k});
    if isnumeric(v) || islogical(v), text = mat2str(v,16); else, text = char(string(v)); end
    fprintf(fid,'%s=%s\n',f{k},text);
end
end
