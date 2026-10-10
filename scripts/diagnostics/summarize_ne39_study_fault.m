function report = summarize_ne39_study_fault()
%SUMMARIZE_NE39_STUDY_FAULT สรุป fault runs จริง ไม่ใช้ผลย้อนหลังตัดสิน switching.
pf_init_paths();
root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
out = fullfile(root,'output','diagnostics','ne39_tamu');
rows = struct([]);
for ns = [5 1]
    name = sprintf('study_fault_%dsg_%dibr.mat',ns,10-ns);
    data = load(fullfile(out,name),'r','s','e');
    r = data.r; s = data.s;
    [dev,~] = stability.build_mixed_resource_devices(s.case_data,s.resources,s.scenario_opt);
    nt = numel(r.t); nd = numel(dev);
    f = nan(nd,nt); rocof = f; rocov = f; raw_rocov = f;
    valid = false(nd,nt); vdc = f; current = f; severity = f;
    machine_current = f; dc_current = f; dc_limit = nan(nd,1);
    acc = stability.EtFcsRateAccumulator(struct('fbase',60,'warmup_s',.02, ...
        'rocov_tau_s',.02));
    xo = [0 cumsum([dev.nx])]; uo = [0 cumsum([dev.nu])];
    for j = 1:nt
        sample = repmat(struct('device_index',0,'mode','','online',false, ...
            'f_hz',NaN,'v_mag',NaN,'fdot_hz_s',NaN),1,nd);
        ec = r.event_context_history{j};
        for k = 1:nd
            d = dev(k); x = r.x_traj(xo(k)+(1:d.nx),j);
            u = r.u_history(uo(k)+(1:d.nu),j); y = r.y_traj(:,j);
            freq = stability.et_fcs_device_frequency(d,r.t(j),x,y,u,ec,s.case_data);
            V = abs(complex(y(2*d.bus_position-1),y(2*d.bus_position)));
            sample(k) = struct('device_index',k,'mode',freq.mode, ...
                'online',freq.online,'f_hz',freq.f_hz,'v_mag',V,'fdot_hz_s',freq.fdot_hz_s); %#ok<AGROW>
            f(k,j) = freq.f_hz;
            I = d.current_injection(r.t(j),x,y,u,ec);
            current(k,j) = abs(I);
            severity(k,j) = min(1,.5*abs(V-1)/.1+.5*abs(freq.f_hz-60)/.5);
            if startsWith(d.device_id,'IBR')
                vdc(k,j) = x(3); dc_current(k,j) = x(17);
                machine_current(k,j) = abs(I)*d.provenance.params.kappa;
                design = s.case_data.study_capability.records;
                design = design(strcmp({design.resource_id},d.device_id));
                dc_limit(k) = design.Idc_continuous_design_pu;
            end
        end
        [acc,staged] = acc.step(r.t(j),sample,true);
        for k = 1:nd
            rocof(k,j) = staged(k).rocof_hz_s;
            rocov(k,j) = staged(k).rocov_pu_s;
            valid(k,j) = staged(k).valid;
        end
    end
    series = acc.rates();
    % ไม่มี mode change ใน fault-only: แต่ event duplicates ไม่เพิ่ม rate rows.
    for k = 1:nd
        for j = 1:nt
            z = find(abs(series.t(:,k)-r.t(j))<1e-12,1,'last');
            if ~isempty(z) && isfinite(rocov(k,j))
                raw_rocov(k,j) = series.rocov_pu_raw_s(z,k);
            end
        end
    end
    diag = struct('t',r.t,'resource_ids',{{dev.device_id}},'f_Hz',f, ...
        'rocof_Hz_s',rocof,'rocov_filtered_pu_s',rocov,'rocov_raw_pu_s',raw_rocov, ...
        'rate_valid',valid,'Vdc_pu',vdc,'I_system_pu',current,'severity',severity, ...
        'I_machine_pu',machine_current,'Idc_pu',dc_current,'Idc_design_pu',dc_limit, ...
        'severity_definition','sat(.5*abs(V-1)/.1+.5*abs(f-60)/.5)', ...
        'measurement_scope','post-run causal reconstruction; not online switching', ...
        'jump_diagnostics',acc.jump_diagnostics());
    save(fullfile(out,sprintf('study_fault_%dsg_%dibr_metrics.mat',ns,10-ns)),'diag');
    row = struct('scenario_id',s.scenario_id,'converged',r.converged, ...
        't_end_s',r.t(end),'fault_bus',data.e.fault_bus, ...
        'fault_on_s',data.e.fault_on,'fault_clear_s',data.e.fault_clear, ...
        'voltage_min_pu',min(r.bus_voltage_magnitude,[],'all'), ...
        'voltage_max_pu',max(r.bus_voltage_magnitude,[],'all'), ...
        'frequency_min_Hz',min(f,[],'all','omitnan'), ...
        'frequency_max_Hz',max(f,[],'all','omitnan'), ...
        'Vdc_min_pu',min(vdc,[],'all','omitnan'), ...
        'Vdc_max_pu',max(vdc,[],'all','omitnan'), ...
        'IBR_current_max_machine_pu',max(machine_current,[],'all','omitnan'), ...
        'IBR_current_limit_exceeded',any(machine_current>1.2+1e-6,'all'), ...
        'dc_design_current_exceeded',any(dc_current>dc_limit+1e-6,'all'), ...
        'rocof_max_abs_Hz_s',max(abs(rocof(valid)),[],'omitnan'), ...
        'rocov_filtered_max_abs_pu_s',max(abs(rocov(valid)),[],'omitnan'), ...
        'switching_enabled',false,'switching_certified',false, ...
        'hardware_verified',false,'capability','PROJECT_DERIVED_STUDY_DESIGN');
    rows = [rows;row]; %#ok<AGROW>
    fprintf('%s: V=[%.4f %.4f], f=[%.4f %.4f], Vdc=[%.4f %.4f]\n', ...
        row.scenario_id,row.voltage_min_pu,row.voltage_max_pu, ...
        row.frequency_min_Hz,row.frequency_max_Hz,row.Vdc_min_pu,row.Vdc_max_pu);
end
report = struct('scope','fault-only classical-reduction study; no switching comparison', ...
    'cases',rows);
fid = fopen(fullfile(out,'study_fault_summary.json'),'w');
if fid<0, error('ne39Study:write','เขียน summary ไม่ได้'); end
cleanup = onCleanup(@()fclose(fid));
fwrite(fid,jsonencode(report,PrettyPrint=true),'char');
end
