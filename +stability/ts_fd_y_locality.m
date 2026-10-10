function loc = ts_fd_y_locality(dae, x, u, event_context, t)
%TS_FD_Y_LOCALITY ตรวจ registered structural locality และ probe ต่างบัส.
%
% ทุก device ต้องมี structural declaration ว่าอ่าน y เฉพาะ PCC ของตัวเอง.
% probe ที่ state เดียวไม่พิสูจน์ locality ทั่ว nonlinear domain จึงใช้เป็น
% negative cross-check เพิ่มเท่านั้น: perturb Re/Im ต่างบัสแยกกันและต้องได้
% output เดิมทุก bit. หากไม่มี declaration หรือพบ foreign response ให้ fallback.
%
% เมื่อ locality contract เป็นจริง differential rows ขึ้นกับ PCC เดิมเท่านั้น;
% KCL rows ของ y column ที่บัส b มาจาก {i:Ynet(i,b)~=0}. กลุ่มที่ row sets
% ไม่ทับกันจึงสร้าง Jacobian เดียวกับ per-column FD; fd_structure_check ตรวจซ้ำได้.
%
% probe ใช้ประมาณ 2*nd*(nb-1) evaluations. caller cache เฉพาะ entry ล่าสุดโดย
% isequaln ของ devices/context จริง ไม่ hash สรุป captured workspace. cache ไม่
% รวม x/u/time จึงอาศัย structural declaration ไม่ใช่ probe เป็น global proof.
% topology ไม่อยู่ใน locality key; KCL row sets คำนวณจาก Ynet ปัจจุบันทุก call.
%
% Classification: PROJECT_DERIVED cross-check บน SOURCE_IMPLEMENTED callbacks.
% ไม่เปลี่ยน residual, tolerance หรือ state contract.

arguments
    dae struct
    x double
    u double
    event_context struct
    t double = 0
end

loc = struct('local',false,'reason','','n_devices',0,'n_buses',0, ...
    'step',0,'worst_change',0,'classification','PROJECT_DERIVED');

required = {'devices','device_offsets','u_offsets','bus_map','nb'};
for k = 1:numel(required)
    if ~isfield(dae,required{k})
        loc.reason = ['missing_' required{k}];
        return;
    end
end
if ~isstruct(dae.devices) || ~isfield(dae.devices,'nx') || ...
        ~isfield(dae.devices,'f') || ~isfield(dae.devices,'current_injection')
    loc.reason = 'devices_without_abi';
    return;
end

offset = double(dae.device_offsets(:)');
uoffset = double(dae.u_offsets(:)');
bmap = double(dae.bus_map(:)');
nd = numel(dae.devices);
nb = double(dae.nb);
if numel(offset) ~= nd || numel(uoffset) ~= nd || numel(bmap) ~= nd || ...
        nd < 1 || ~isfinite(nb) || nb < 1
    loc.reason = 'device_table_length_mismatch';
    return;
end
if numel(x) < max(offset + double([dae.devices.nx]))
    loc.reason = 'state_vector_too_short';
    return;
end
if ~isfield(dae,'y0') || numel(dae.y0) ~= 2*nb
    loc.reason = 'ny_not_two_per_bus';
    return;
end

% Registered structural declaration for every device. A probe at one state is
% NOT a proof (a nonlinear device could have zero foreign response here and a
% nonzero one elsewhere), so locality requires an explicit registered
% declaration; any undeclared device fails closed to the per-column FD.
for k = 1:nd
    dev_k = dae.devices(k);
    [dec, di] = stability.algebraic_y_locality_declaration(dev_k);
    if ~dec
        loc.reason = sprintf('undeclared device %d (%s=%s)',k,di.source,di.key);
        loc.n_devices = nd; loc.n_buses = nb;
        return;
    end
end

% Probe step: a small but comfortably above round-off absolute perturbation.
% Device outputs are O(1) pu, so 1e-6 clears double round-off (~2.2e-16) by ~10
% decades while staying in the linear regime, so a genuinely local device shows
% EXACTLY zero change (bit-identical inputs). This probe is an ADDITIONAL
% cross-check on the declared set, never a substitute for the declaration.
h = 1e-6;
% device ที่ local ได้ input ณ PCC เดิมทุก bit จึงต้องได้ output เดิมทุก bit.
% ไม่ใช้ tolerance กับ raw change เพราะจะซ่อน foreign derivative ที่เล็กกว่า h.
sensitivity_tol = 0;

y0 = dae.y0(:);
dev = dae.devices;
worst = 0;
for k = 1:nd
    nxk = double(dev(k).nx); nuk = double(dev(k).nu);
    xk = x(offset(k)+(1:nxk));
    if nuk > 0
        uk = u(uoffset(k)+(1:nuk));
    else
        uk = zeros(0,1);
    end
    f_ref = dev(k).f(t, xk, y0, uk, event_context);
    I_ref = dev(k).current_injection(t, xk, y0, uk, event_context);
    if any(~isfinite(f_ref)) || ~isfinite(I_ref)
        loc.reason = sprintf('nonfinite_at_base_device_%d',k);
        return;
    end
    bk = bmap(k);
    for b = 1:nb
        if b == bk, continue; end
        % perturb แต่ละ coordinate แยกกัน ป้องกัน Re/Im cancellation.
        for column=2*b-1:2*b
            yp=y0; yp(column)=yp(column)+h;
            df=dev(k).f(t,xk,yp,uk,event_context)-f_ref;
            dI=dev(k).current_injection(t,xk,yp,uk,event_context)-I_ref;
            if any(~isfinite(df)) || ~isfinite(dI)
                loc.reason=sprintf('nonfinite_probe_device_%d_bus_%d',k,b);
                return;
            end
            ch=max([norm(df,inf),abs(dI)]); worst=max(worst,ch);
            if ch>sensitivity_tol
                loc.reason=sprintf( ...
                    'device %d reads foreign bus %d (change %.3e > %.1e)', ...
                    k,b,ch,sensitivity_tol);
                loc.n_devices=nd; loc.n_buses=nb; loc.step=h;
                loc.worst_change=worst;
                return;
            end
        end
    end
end

loc.local = true;
loc.reason = 'all_devices_y_local_to_own_bus';
loc.n_devices = nd;
loc.n_buses = nb;
loc.step = h;
loc.worst_change = worst;
end
