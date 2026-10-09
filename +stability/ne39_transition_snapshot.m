function evidence = ne39_transition_snapshot(t,x,y,u,ec,dae,resources,case_data,bounds)
%NE39_TRANSITION_SNAPSHOT ตรวจ state จริง ไม่ใช่ certificate ของทั้ง trajectory.
% พลังงาน pu-s บน converter MVA base; Pac อ่านกลับจาก DC RHS จริง.
arguments
    t (1,1) double {mustBeFinite}
    x (:,1) double
    y (:,1) double
    u (:,1) double
    ec (1,1) struct
    dae (1,1) struct
    resources struct
    case_data (1,1) struct
    bounds (1,1) struct
end
evidence=struct('status','UNKNOWN','reason','ข้อมูลไม่ครบ','records',struct([]), ...
    'classification','PROJECT_DERIVED','trajectory_certified',false, ...
    'complete',false,'nonvoltage_status','UNKNOWN','voltage_reference',struct());
if ~all(isfield(bounds,{'v_min','v_max','f_min','f_max'})) || ...
        ~all(isfield(dae,{'devices','device_offsets','u_offsets'})) || ...
        numel(resources)~=numel(dae.devices)
    return;
end
for name={'v_min','v_max','f_min','f_max'}
    validateattributes(bounds.(name{1}),{'numeric'},{'scalar','finite','real','positive'});
end
if bounds.v_min>=bounds.v_max || bounds.f_min>=bounds.f_max
    error('stability:ne39_transition_snapshot:bounds','ขอบเขต V/f ไม่ถูกต้อง');
end
if any(~isfinite([x;y;u])) || ~isreal([x;y;u])
    evidence.status='FAIL'; evidence.reason='state ไม่ finite/real'; return;
end
Sbase=case_data.mpc.baseMVA;
if numel(y)~=2*size(case_data.mpc.bus,1)
    evidence.reason='network voltage dimensions ไม่ตรง'; return;
end
vm=abs(complex(y(1:2:end),y(2:2:end)));
network_valid=all(isfinite(vm) & vm>0);
network_ok=network_valid && all(vm>=bounds.v_min & vm<=bounds.v_max);
evidence.voltage_reference=struct('bounds_pu',[bounds.v_min bounds.v_max], ...
    'bus_ids',case_data.mpc.bus(:,1),'magnitude_pu',vm, ...
    'out_of_band',vm<bounds.v_min | vm>bounds.v_max,'pass',network_ok, ...
    'scope','PROJECT_OPERATING_REFERENCE_NOT_UNIVERSAL_TRANSIENT_LIMIT');
rows=struct([]);
try
    for k=1:numel(dae.devices)
        d=dae.devices(k); r=resources(k);
        if ~strcmp(char(d.device_id),char(r.resource_id))
            evidence.reason='resource alignment ไม่ตรง'; return;
        end
        xd=x(dae.device_offsets(k)+(1:d.nx));
        ud=u(dae.u_offsets(k)+(1:d.nu));
        rec=d.reconstruct(t,xd,y,ud,ec);
        if ~isfield(rec,'online') || ~isscalar(rec.online), return; end
        if ~rec.online, continue; end
        V=complex(y(2*d.bus_position-1),y(2*d.bus_position));
        I=d.current_injection(t,xd,y,ud,ec);
        pq=V*conj(I)*Sbase;
        fr=stability.et_fcs_device_frequency(d,t,xd,y,ud,ec,case_data);
        row=struct('resource_id',char(d.device_id),'mode',char(rec.mode), ...
            'P_MW',real(pq),'Q_MVAr',imag(pq),'V_pu',abs(V),'f_Hz',fr.f_hz, ...
            'I_converter_pu',NaN,'Vdc_pu',NaN,'Idc_pu',NaN, ...
            'source_power_MW',NaN,'Pac_converter_pu',NaN, ...
            'capacitor_energy_pu_s',NaN,'source_inductor_energy_pu_s',NaN, ...
            'stored_energy_MJ',NaN,'stored_energy_rate_pu',NaN, ...
            'source_minus_losses_pu',NaN,'energy_rhs_error_pu',NaN, ...
            'ac_dc_power_error_pu',NaN, ...
            'pass',false,'failure','','nonvoltage_pass',false,'checks',struct());
        checks=struct('electrical_evidence',isscalar(I) && isfinite(I) && isfinite(pq), ...
            'frequency_evidence',fr.online && isfinite(fr.f_hz), ...
            'voltage',abs(V)>=bounds.v_min && abs(V)<=bounds.v_max, ...
            'frequency',fr.f_hz>=bounds.f_min && fr.f_hz<=bounds.f_max);
        if ~isfield(r.limits,'Pmax_MW') || ~isscalar(r.limits.Pmax_MW) || ...
                ~isfinite(r.limits.Pmax_MW)
            evidence.reason='ขาด P capability'; return;
        end
        checks.active_power=real(pq)>=0 && real(pq)<=r.limits.Pmax_MW;
        if strcmpi(r.resource_type,'ibr')
            if ~strcmp(d.device_type,'ibr_eecon49_dual') || ...
                    ~isfield(d.provenance,'branch_params'), return; end
            branch=lower(char(rec.mode));
            p=d.provenance.branch_params.(branch); dc=p.dc_source;
            required={'fixed_plant','source_state','Edc','Rdc','Cdc','tau_s', ...
                'Idc_max','Psource_max','Vdc_max','Rch'};
            if ~all(isfield(dc,required)) || ~dc.fixed_plant || ~dc.source_state
                evidence.reason='ขาด fixed dynamic DC plant'; return;
            end
            other='gfm'; if strcmp(branch,'gfm'), other='gfl'; end
            dc_other=d.provenance.branch_params.(other).dc_source;
            for field=required
                if ~isfield(dc_other,field{1}) || ...
                        ~isequaln(dc.(field{1}),dc_other.(field{1}))
                    evidence.reason='GFL/GFM DC plant ไม่ตรงกัน'; return;
                end
            end
            vals=[dc.Edc dc.Rdc dc.Cdc dc.tau_s dc.Idc_max ...
                dc.Psource_max dc.Vdc_max dc.Rch p.Mbase];
            if any(~isfinite(vals)) || any(vals<=0), return; end
            if ~all(isfield(r.limits,{'ImaxF','Qmax_MVAr'})) || ...
                    ~isscalar(r.limits.ImaxF) || ~isfinite(r.limits.ImaxF) || ...
                    r.limits.ImaxF<=0 || ~isscalar(r.limits.Qmax_MVAr) || ...
                    ~isfinite(r.limits.Qmax_MVAr)
                evidence.reason='ขาด AC capability'; return;
            end
            ji=find(strcmp(d.state_names,'I_dc'));
            if numel(ji)~=1, return; end
            v=xd(3); j=xd(ji); dx=d.f(t,xd,y,ud,ec);
            ich=max(0,v-dc.Vdc_max)/dc.Rch;
            pac=v*(j-ich-dc.Cdc*dx(3));
            % ตรวจข้าม AC/DC: transient Pac ต้องรวม filter magnetic-energy rate.
            wb=2*pi*case_data.base_values.frequency_Hz;
            pac_ac=real(pq)/p.Mbase+p.Rf*(xd(1)^2+xd(2)^2)+ ...
                (p.Lf/wb)*(xd(1)*dx(1)+xd(2)*dx(2));
            % Ldc=tau_s*Rdc: รวมพลังงาน inductor เพื่อไม่ตกหล่น source lag.
            Ecap=.5*dc.Cdc*v^2; Eind=.5*dc.tau_s*dc.Rdc*j^2;
            dE=dc.Cdc*v*dx(3)+dc.tau_s*dc.Rdc*j*dx(ji);
            net=dc.Edc*j-dc.Rdc*j^2-pac-v*ich;
            row.I_converter_pu=abs(I)*Sbase/p.Mbase;
            row.Vdc_pu=v; row.Idc_pu=j;
            row.source_power_MW=dc.Edc*j*p.Mbase;
            row.Pac_converter_pu=pac;
            row.capacitor_energy_pu_s=Ecap; row.source_inductor_energy_pu_s=Eind;
            row.stored_energy_MJ=(Ecap+Eind)*p.Mbase;
            row.stored_energy_rate_pu=dE; row.source_minus_losses_pu=net;
            row.energy_rhs_error_pu=abs(dE-net);
            row.ac_dc_power_error_pu=abs(pac-pac_ac);
            checks.dc_voltage=v>1e-6;
            checks.dc_current=j>=0 && j<=dc.Idc_max;
            checks.source_power=dc.Edc*j<=dc.Psource_max;
            checks.ac_current=row.I_converter_pu<=r.limits.ImaxF;
            checks.reactive_power=abs(imag(pq))<=r.limits.Qmax_MVAr;
            checks.dc_energy_balance=isfinite(dE) && row.energy_rhs_error_pu<=1e-8;
            checks.ac_dc_power_balance=row.ac_dc_power_error_pu<=1e-8;
        end
        names=fieldnames(checks); passed=structfun(@(v)logical(v),checks);
        row.pass=all(passed); row.checks=checks;
        row.nonvoltage_pass=all(passed(~strcmp(names,'voltage')));
        if ~row.pass, row.failure=strjoin(names(~passed),','); end
        rows=[rows,row]; %#ok<AGROW>
    end
catch me
    evidence.reason=me.message; evidence.records=rows; return;
end
evidence.records=rows;
if isempty(rows), evidence.reason='ไม่มี online resource'; return; end
evidence.complete=true;
evidence.nonvoltage_status='FAIL';
if network_valid && all([rows.nonvoltage_pass]), evidence.nonvoltage_status='PASS'; end
if network_ok && all([rows.pass])
    evidence.status='PASS'; evidence.reason='snapshot constraints ผ่าน';
else
    evidence.status='FAIL'; evidence.reason='snapshot constraint ไม่ผ่าน';
end
end
