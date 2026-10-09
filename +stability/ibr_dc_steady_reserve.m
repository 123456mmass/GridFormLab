function e = ibr_dc_steady_reserve(devices, resources, eq, case_data)
%IBR_DC_STEADY_RESERVE กำลังสำรอง steady จาก DC plant จริง ไม่ใช่ transition certificate.
% ใช้ฐาน converter; หัก filter loss และคง Q/V ของ candidate ก่อนเทียบ Pmax/current.
% ค่าที่ส่งออกเป็น minimum per-device margin (MW) ไม่บวกกลบเครื่องที่เกิน limit.
e = struct('id','dc_reserve_steady','applicable',true,'status','UNKNOWN', ...
    'value',NaN,'provenance','fixed Thevenin plant; steady only, not transition energy');
Sbase = case_data.mpc.baseMVA;
xo = 0; uo = 0; margins = [];
for k = 1:numel(devices)
    d = devices(k);
    x = eq.x0(xo+(1:d.nx)); u = eq.u_eq(uo+(1:d.nu));
    xo = xo+d.nx; uo = uo+d.nu;
    if ~strcmpi(char(resources(k).resource_type),'ibr'), continue; end
    key = matlab.lang.makeValidName(char(d.device_id),'ReplacementStyle','underscore');
    if isfield(eq.equilibrium_context,'hybrid_state') && ...
            isfield(eq.equilibrium_context.hybrid_state,'device_online') && ...
            isfield(eq.equilibrium_context.hybrid_state.device_online,key) && ...
            ~eq.equilibrium_context.hybrid_state.device_online.(key)
        continue;
    end
    if ~isfield(d.provenance,'branch_params'), return; end
    a = d.provenance.branch_params.gfl; b = d.provenance.branch_params.gfm;
    p = a.dc_source;
    needed = {'fixed_plant','Edc','Rdc','Idc_max','Psource_max','Cdc','tau_s'};
    plant_fields = {'Edc','Rdc','Cdc','tau_s','Vdc_max','Rch','source_state', ...
        'Idc_max','Psource_max'};
    same_plant = all(isfield(p,plant_fields)) && all(isfield(b.dc_source,plant_fields));
    if ~same_plant, return; end
    for field=plant_fields
        same_plant = same_plant && isequaln(p.(field{1}),b.dc_source.(field{1}));
    end
    if ~all(isfield(p,needed)) || ~p.fixed_plant || ...
            ~same_plant || a.Rf~=b.Rf || a.Mbase~=b.Mbase
        return;
    end
    vals = [p.Edc p.Rdc p.Idc_max p.Psource_max p.Cdc p.tau_s a.Mbase];
    if any(~isfinite(vals)) || any(vals<=0), return; end
    L = resources(k).limits;
    if ~all(isfield(L,{'Pmax_MW','ImaxSS'})) || ...
            ~isscalar(L.Pmax_MW) || ~isfinite(L.Pmax_MW) || L.Pmax_MW<=0 || ...
            ~isscalar(L.ImaxSS) || ~isfinite(L.ImaxSS) || L.ImaxSS<=0
        return;
    end
    I = d.current_injection(0,x,eq.y0,u,eq.equilibrium_context);
    V = complex(eq.y0(2*d.bus_position-1),eq.y0(2*d.bus_position));
    power = V*conj(I)*Sbase/a.Mbase;
    v = x(3); si = find(strcmp(d.state_names,'I_dc'));
    if numel(si)~=1 || ~isfinite(v) || v<=0, return; end
    j = x(si); pac = real(power)+a.Rf*abs(I*Sbase/a.Mbase)^2;
    % high-voltage branch และ determinant/trace เป็นเพียง local DC-block checks.
    valid = v>p.Edc/2 && j>=0 && j<=p.Idc_max && ...
        p.Edc*j<=p.Psource_max && pac/v^2<1/p.Rdc && ...
        p.tau_s*pac<p.Cdc*v^2;
    % จำกัดด้วย source current, source input power, fold และ local trace bound.
    jcap = min([p.Idc_max,p.Psource_max/p.Edc,p.Edc/(2*p.Rdc), ...
        p.Cdc*p.Edc/(p.tau_s+p.Cdc*p.Rdc)]);
    pcap = jcap*(p.Edc-p.Rdc*jcap);
    q = imag(power); vm = abs(V); rf = a.Rf;
    if vm<=0 || rf<0, return; end
    rhs = pcap-rf*q^2/vm^2;
    if rhs<0
        pdc = -Inf;
    elseif rf==0
        pdc = rhs;
    else
        % รูป rationalized ป้องกัน cancellation เมื่อ Rf เล็ก.
        pdc = 2*rhs/(1+sqrt(1+4*rf*rhs/vm^2));
    end
    rad = (L.ImaxSS*vm)^2-q^2;
    if rad<0, paclimit=-Inf; else, paclimit=sqrt(rad); end
    ceiling = min([pdc,paclimit,L.Pmax_MW/a.Mbase]);
    margin = (ceiling-real(power))*a.Mbase;
    dx = d.f(0,x,eq.y0,u,eq.equilibrium_context);
    valid = valid && abs(dx(3))<=1e-6 && abs(dx(si))<=1e-6 && ...
        abs((p.Edc-v)/p.Rdc-j)<=1e-6 && ...
        abs(v*j-pac)<=1e-6;
    if ~valid || ~isfinite(margin)
        e.status = 'FAIL'; e.value = -Inf; return;
    end
    margins(end+1) = margin; %#ok<AGROW>
end
if isempty(margins), return; end
e.value = min(margins);
if e.value>=0, e.status='PASS'; else, e.status='FAIL'; end
end
