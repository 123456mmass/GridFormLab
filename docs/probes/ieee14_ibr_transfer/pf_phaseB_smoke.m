%PF_PHASEB_SMOKE  Quick Phase B smoke test (temporary).
%   STATUS: DIAGNOSTIC/WIP. Unreachable from production. Preserved for Phase B
%   equilibrium build/solve diagnostics.
cd('/home/birds/Documents/Power-flow');
path(path, pwd); pf_init_paths;
rehash; clear functions; clear classes;
rehash; rehash path; rehash toolbox;

fprintf('===SG1 composite device build smoke===\n');
c = cases.case_ieee14_1sg_4ibr_auto_vsg();
disp = struct('IBR2',40.0,'IBR3',0.0,'IBR6',0.0,'IBR8',0.0);
modes = struct('device_id', {'IBR2','IBR3','IBR6','IBR8'}, 'mode', {'gfl','gfl','gfl','gfl'});
[devices, meta] = ibr.build_ieee14_sg_ibr_devices(c, modes, disp);
fprintf('num devices: %d (expect 5: SG1+4IBR)\n', numel(devices));
for k=1:numel(devices)
    fprintf('  %s: nx=%d nu=%d type=%s mode=%s\n', devices(k).device_id, devices(k).nx, devices(k).nu, devices(k).device_type, devices(k).mode);
end

fprintf('===Mixed equilibrium (SG_ON, angle-only vcon)===\n');
cfg = struct('sg_status','online', 'device_modes', modes, 'dispatch', disp, 'devices', devices);
r = stability.mixed_equilibrium_solve(c, cfg, struct('verbose',false));
fprintf('converged=%d residual=%.3e rcond=%.3e fail=%s\n', r.converged, r.residual_norm, r.rcond, r.failure_id);
if r.converged
    V1 = r.y0(1) + 1i*r.y0(2);
    fprintf('V1 = %.6f + j%.6f (|V1|=%.6f, angle=%.6f deg)\n', real(V1), imag(V1), abs(V1), rad2deg(angle(V1)));
    fprintf('Re(V1) (free unknown) = %.6f (expect near 1.06 but SOLVED, not fixed)\n', r.y0(1));
    fprintf('Im(V1) (angle ref, fixed) = %.6g (expect 0)\n', r.y0(2));
    % Limit checks per device
    if isfield(r.limit_checks,'devices') && isfield(r.limit_checks.devices,'SG1')
        sg = r.limit_checks.devices.SG1;
        fprintf('SG1: P=%.3f MW Q=%.3f MVAr I=%.4f pu Vbus=%.4f\n', sg.P_MW, sg.Q_MVAr, sg.I_pu, sg.Vbus_pu);
    end
    for did = {'IBR2','IBR3','IBR6','IBR8'}
        if isfield(r.limit_checks.devices, did{1})
            d = r.limit_checks.devices.(did{1});
            fprintf('%s: P=%.3f MW Q=%.3f MVAr I=%.4f pu Vbus=%.4f\n', did{1}, d.P_MW, d.Q_MVAr, d.I_pu, d.Vbus_pu);
        end
    end
end
