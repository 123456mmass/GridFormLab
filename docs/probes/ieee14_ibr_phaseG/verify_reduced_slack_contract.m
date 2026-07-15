%VERIFY_REDUCED_SLACK_CONTRACT  Diagnostic-only fixed-P versus slack-P oracle.
% This script is off the production MATLAB path.  It uses project-owned
% equations and a small local damped Newton implementation to expose whether
% replacing one KCL row by an angle gauge hides an active-power imbalance.

restoredefaultpath;
root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
cd(root);
pf_init_paths;

c = cases.case_ieee14_1sg_4ibr_auto_vsg();
modes = struct('device_id',{'IBR2','IBR3','IBR6','IBR8'}, ...
    'mode',{'GFM','gfl','gfl','gfl'});
dispatch = struct('IBR2',109.7,'IBR3',49.8,'IBR6',49.8,'IBR8',49.8);
devices = ibr.build_ieee14_sg_ibr_devices(c, modes, dispatch);
for k = 1:numel(devices)
    if strcmp(devices(k).device_id,'SG1')
        devices(k).initial_online = false;
        devices(k).mode = 'breaker_open';
        devices(k).initial_mode = 'breaker_open';
    end
end
dae = stability.composite_dae(c, devices, struct('load_model','cz_p_cz_q'));

ref_device = find(strcmp({devices.device_id},'IBR2'),1);
ref_bus = devices(ref_device).bus_position;
gauge_var = 2*ref_bus;
free_y = setdiff(1:numel(dae.y0),gauge_var,'stable');

online_ibr = find(~strcmp({devices.device_id},'SG1'));
gfm_devices = online_ibr(strcmpi(string({devices(online_ibr).mode}),"gfm"));
fprintf('diagnostic devices: online_ibr=%s gfm=%s modes=%s\n', ...
    mat2str(online_ibr),mat2str(gfm_devices),strjoin(string({devices(online_ibr).mode}),','));
flat_y = zeros(size(dae.y0));
flat_y(1:2:end) = abs(dae.y0(1:2:end) + 1i*dae.y0(2:2:end));
flat_y(gauge_var) = 0;

% A: all active-power references fixed; omit the gauge-bus imaginary KCL row.
zA0 = [flat_y(free_y); zeros(numel(gfm_devices),1)];
funA = @(z) reduced_residual(z,false,dae,devices,online_ibr,gfm_devices, ...
    ref_device,free_y,gauge_var);
[zA,okA,nA] = local_newton(funA,zA0,1e-10,80,3e-6);
[rA,kclA,pA] = reduced_residual(zA,false,dae,devices,online_ibr,gfm_devices, ...
    ref_device,free_y,gauge_var);

% B: reference-GFM active power is an unknown; retain every physical KCL row.
% The fixed-P reduced root is a deterministic continuation seed.  It is not
% accepted as a physical solution because its omitted KCL row is checked above.
zB0 = [zA; devices(ref_device).u0(1)];
funB = @(z) reduced_residual(z,true,dae,devices,online_ibr,gfm_devices, ...
    ref_device,free_y,gauge_var);
[JB,sB] = local_fd_diagnostics(funB,zB0,3e-6);
[zB,okB,nB] = local_newton(funB,zB0,1e-10,80,3e-6);
[rB,kclB,pB] = reduced_residual(zB,true,dae,devices,online_ibr,gfm_devices, ...
    ref_device,free_y,gauge_var);

fprintf('fixed-P omitted-row: converged=%d iter=%d reduced=%.12g omitted_KCL=%.12g P_ref=%.9f\n', ...
    okA,nA,norm(rA,inf),abs(kclA(gauge_var)),pA);
fprintf('slack-P all-KCL:      converged=%d iter=%d residual=%.12g max_KCL=%.12g P_ref=%.9f\n', ...
    okB,nB,norm(rB,inf),norm(kclB,inf),pB);
fprintf('slack-P initial J:     size=%dx%d rank=%d rcond=%.12g smin=%.12g\n', ...
    size(JB,1),size(JB,2),rank(JB),rcond(JB),min(sB));

function [r,kcl,p_ref] = reduced_residual(z,slack_p,dae,devices,online_ibr, ...
        gfm_devices,ref_device,free_y,gauge_var)
ny = numel(dae.y0);
nq = numel(gfm_devices);
y = zeros(ny,1);
y(free_y) = z(1:numel(free_y));
y(gauge_var) = 0;
q = z(numel(free_y)+(1:nq));
if slack_p
    p_ref = z(end);
else
    p_ref = devices(ref_device).u0(1);
end
V = y(1:2:end) + 1i*y(2:2:end);
Ibus = zeros(dae.nb,1);
for ii = 1:numel(online_ibr)
    dk = online_ibr(ii);
    P = devices(dk).u0(1);
    Q = devices(dk).u0(2);
    iq = find(gfm_devices==dk,1);
    if ~isempty(iq)
        Q = q(iq);
        if dk == ref_device, P = p_ref; end
    end
    vb = V(devices(dk).bus_position);
    Ibus(devices(dk).bus_position) = Ibus(devices(dk).bus_position) + ...
        conj((P + 1i*Q)/vb);
end
kcl_complex = dae.Ynet*V - Ibus;
kcl = zeros(ny,1);
kcl(1:2:end) = real(kcl_complex);
kcl(2:2:end) = imag(kcl_complex);
v_constraints = zeros(nq,1);
for iq = 1:nq
    dk = gfm_devices(iq);
    v_constraints(iq) = abs(V(devices(dk).bus_position))^2 - devices(dk).u0(3)^2;
end
if slack_p
    r = [kcl;v_constraints];
else
    r = [kcl(free_y);v_constraints];
end
end

function [z,converged,iterations] = local_newton(fun,z,tol,max_iter,h)
converged = false;
iterations = 0;
for k = 0:max_iter
    r = fun(z);
    if norm(r,inf) < tol
        converged = true;
        iterations = k;
        return;
    end
    J = zeros(numel(r),numel(z));
    for j = 1:numel(z)
        zp = z; zm = z;
        zp(j) = zp(j)+h; zm(j) = zm(j)-h;
        J(:,j) = (fun(zp)-fun(zm))/(2*h);
    end
    dz = -(J\r);
    accepted = false;
    alpha = 1;
    for ls = 1:20
        trial = z + alpha*dz;
        if norm(fun(trial),inf) < norm(r,inf)
            z = trial;
            accepted = true;
            break;
        end
        alpha = alpha/2;
    end
    if ~accepted
        iterations = k;
        return;
    end
end
iterations = max_iter;
end

function [J,s] = local_fd_diagnostics(fun,z,h)
r = fun(z);
J = zeros(numel(r),numel(z));
for j = 1:numel(z)
    zp=z; zm=z; zp(j)=zp(j)+h; zm(j)=zm(j)-h;
    J(:,j)=(fun(zp)-fun(zm))/(2*h);
end
s=svd(J);
end
