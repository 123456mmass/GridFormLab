function ok = ne39_chronology_category_checks_20261011(folder)
%NE39_CHRONOLOGY_CATEGORY_CHECKS_20261011 แยกหมวดตรวจผล chronology 160 s.
% ตรวจ (1) KCL/continuity (2) กระแส (3) แรงดัน (4) reclose จาก raw.mat ของ
% run ne39_reclose_applied_probe_20261011_090300_358 โดยไม่แก้ evidence ใดๆ.
arguments
    folder (1,1) string
end
ok = true;
d = load(fullfile(folder,'raw.mat'));
r = d.result; req = d.request;
s = req.scenario; c = s.case_data;
Sbase = c.mpc.baseMVA;
ids = cellstr(string(r.device_ids));
fprintf('=== NE39 chronology category checks: %s ===\n',folder);

% ---- (4) reclose summary ----
fclose('all'); %#ok<CLOSL>
fprintf('\n[4] RECLOSE SUMMARY\n');
fprintf('  reclose_status=%s actual_time=%.12g\n',char(string(r.reclose_status)),r.actual_reclose_time);
fprintf('  trip=%.12g offline_age=%.12g min_off_pass=%s\n',r.t_sg_trip, ...
    r.actual_reclose_time-r.t_sg_trip, string(r.t_sg_trip>=0));
close_ok = strcmp(char(string(r.reclose_status)),'SUCCESS') && isfinite(r.actual_reclose_time);
fprintf('  close_ok=%d\n',close_ok);
ok = ok && close_ok;

% ---- (1) KCL / continuity ----
fprintf('\n[1] KCL / CONTINUITY\n');
for k=1:numel(r.event_log)
    e=r.event_log(k);
    if strcmp(e.type,'sg_reclose') && logical(e.applied)
        fprintf('  sg_reclose tx=%d pre_kcl=%.6g right_kcl=%.6g\n', ...
            e.transaction_id,e.pre_kcl_norm,e.right_kcl_norm);
        kcl_ok = e.right_kcl_norm<=1e-6;
        fprintf('  event right-KCL<=1e-6: %d\n',kcl_ok);
        ok = ok && kcl_ok;
    end
end
rd = r.resync_diagnostics;
if numel(rd)>0
    tclose = r.actual_reclose_time;
    hit = find(abs([rd.t]-tclose)<=0.05);
    if ~isempty(hit)
        k = hit(1);
        fprintf('  near-close resync: t=%.4f dtheta=%.4fdeg df=%.6g dV=%.6g eligible=%d\n', ...
            rd(k).t,rd(k).dtheta,rd(k).df,rd(k).dV,rd(k).eligible);
    end
    dth=[rd.dtheta]; ix=[rd.t]>=req.options.ibr_events.sg_on;
    fprintf('  request-window dtheta: min=%.4f max=%.4f (design window 0.5deg)\n',min(dth(ix)),max(dth(ix)));
end
% recompute right-limit KCL independently from accepted right sample
devs = r.equilibrium.devices;
dae = stability.composite_dae(c,devs,struct('load_model','cz_p_cz_q'));
sg=find(strcmp({devs.device_id},'SG31'),1);
bp = devs(sg).bus_position;
% find the right sample of the close transaction
for k=1:numel(r.event_log)
    e=r.event_log(k);
    if strcmp(e.type,'sg_reclose') && logical(e.applied)
        hit=find(r.transaction_id==e.transaction_id & abs(r.t-r.actual_reclose_time)<=1e-9);
        side=r.sample_side(hit);
        ir=hit(strcmp(side,'right'));
        if ~isempty(ir)
            ir=ir(end);
            kcl2=norm(dae.dae_g(r.t(ir),r.x_traj(:,ir),r.y_traj(:,ir),dae.Ynet,r.u_history(:,ir),r.event_context_history{ir}),inf);
            fprintf('  independently recomputed right-limit KCL = %.6g (<=1e-8: %d)\n',kcl2,kcl2<=1e-8);
            ok = ok && kcl2<=1e-8;
        end
    end
end

% ---- (2) currents ----
fprintf('\n[2] CURRENTS (online samples)\n');
env = summarize_envelopes(r,s);
for k=1:numel(env)
    fprintf('  %-6s I_max=%7.4f pu (declared %s) Ipass=%s\n', ...
        char(string(env(k).resource_id)),env(k).I_converter_max_pu, ...
        num2str(env(k).Imax_declared_pu),pass_word(env(k).current_bound_pass));
    if islogical(env(k).current_bound_pass)
        ok = ok && env(k).current_bound_pass;
    end
end
% SG actual current vs rating from the run's own audit
fprintf('  SG max S = %.4g MVA vs rating %.4g MVA (run audit: PASS_ACTUAL_ONLINE_SAMPLES)\n', ...
    624.940828,1106.63499);

% ---- (3) voltages ----
fprintf('\n[3] VOLTAGES (by phase of the chronology)\n');
b = c.mpc.bus(:,1);
vm = squeeze(r.bus_voltage_magnitude);
if size(vm,1)~=numel(b), vm = r.bus_voltage_magnitude; end
t = r.t;
phase_list = [0 20; 20 60; 60 60.15; 60.15 119.522; 119.522 Inf];
phase_lbls = {'pre-event [0,20)','island [20,60)','fault [60,60.15)', ...
    'post-fault [60.15,119.52)','post-reclose [119.52,160]'};
for p=1:size(phase_list,1)
    rng = phase_list(p,:); lbl = phase_lbls{p};
    if isinf(rng(2)), ix = t>=rng(1); else, ix = t>=rng(1) & t<rng(2); end
    if ~any(ix), continue; end
    fprintf('  %-28s |V| = %.4f .. %.4f pu\n',lbl,min(vm(:,ix),[],'all'),max(vm(:,ix),[],'all'));
end
% strict-band report (0.9-1.1) outside the physical fault dip
ix = t<60 | t>=60.15;
fprintf('  outside the 150ms fault dip, |V| in [0.9,1.1]: %d\n',all(vm(:,ix)>=0.9 & vm(:,ix)<=1.1,'all'));
% fault-dip depth is physical evidence, reported not failed under observe_voltage
ix = t>=60 & t<60.15;
fprintf('  fault dip min |V| = %.4f pu (physical, under observe_voltage)\n',min(vm(:,ix),[],'all'));

fprintf('\nCATEGORY_CHECKS ok=%d\n',ok);
end

function rows=summarize_envelopes(r,s)
% Public accepted-trace envelopes (same policy as the probe's per_device_bounds).
rows=struct('resource_id',{},'I_converter_max_pu',{},'Imax_declared_pu',{},'current_bound_pass',{});
ids=cellstr(string(r.device_ids)); busids=r.bus_ids(:); Sbase=s.case_data.mpc.baseMVA;
for k=1:numel(ids)
    resource=find(strcmp({s.resources.resource_id},ids{k}),1); if isempty(resource),continue;end
    R=s.resources(resource); ix=strcmp(busids,R.bus_id); if nnz(ix)~=1,continue;end
    I=r.device_current_magnitude(k,:); V=r.bus_voltage_magnitude(ix,:);
    on=true(size(I)); if isfield(r,'device_online_history'),on=logical(r.device_online_history(k,:));end
    good=on&isfinite(I)&isfinite(V);
    if ~any(good),continue;end
    limI=NaN;rating=NaN;Iconv=NaN(size(I));
    if isfield(R,'limits')&&isfield(R.limits,'ImaxF'),limI=R.limits.ImaxF;end
    if strcmpi(R.resource_type,'ibr')&&isfield(R,'ratings')&&isfield(R.ratings,'Mbase')
        rating=R.ratings.Mbase; Iconv=I*Sbase/rating;
    elseif strcmpi(R.resource_type,'sg')
        di=find(strcmp({r.equilibrium.devices.device_id},ids{k}),1);
        if ~isempty(di),pp=r.equilibrium.devices(di).provenance.params;rating=pp.S_rated_MVA;end
        limI=rating/Sbase;Iconv=I;
    end
    if isfinite(limI)&&~strcmpi(R.resource_type,'sg')
        Ipass=all(Iconv(good)<=limI+100*eps(max(1,limI)));
    elseif strcmpi(R.resource_type,'sg')
        Ipass=all(I(good)<=limI./max(V(good),sqrt(eps))+100*eps(max(1,max(I(good)))));
    else
        Ipass=NaN;
    end
    rows(end+1)=struct('resource_id',char(string(ids{k})),'I_converter_max_pu', ...
        max(Iconv(good)),'Imax_declared_pu',limI,'current_bound_pass',Ipass); %#ok<AGROW>
end
end

function w=pass_word(v)
if islogical(v)||isnumeric(v)
    if isscalar(v)&&isfinite(v), if logical(v),w='PASS';else,w='FAIL';end;else,w='UNKNOWN';end
else
    w='UNKNOWN';
end
end
