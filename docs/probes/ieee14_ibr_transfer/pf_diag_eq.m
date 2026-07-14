%PF_DIAG_EQ  Diagnose mixed equilibrium singular Jacobian (temporary).
%   STATUS: DIAGNOSTIC/WIP. Unreachable from production. Preserved for rcond=NaN
%   root-cause evidence (proves RCOND=NaN not RCOND≈0).
cd('/home/birds/Documents/Power-flow');
path(path, pwd); pf_init_paths;
rehash; clear functions; clear classes;
rehash; rehash path; rehash toolbox;

c = cases.case_ieee14_1sg_4ibr_auto_vsg();
disp = struct('IBR2',40.0,'IBR3',0.0,'IBR6',0.0,'IBR8',0.0);
modes = struct('device_id',{'IBR2','IBR3','IBR6','IBR8'},'mode',{'gfl','gfl','gfl','gfl'});
[devices, ~] = ibr.build_ieee14_sg_ibr_devices(c, modes, disp);
cfg = struct('sg_status','online','device_modes',modes,'dispatch',disp,'devices',devices);

% Build the dae manually to inspect residual/jacobian.
vcon = struct('vars',2,'rows',2,'eq',@(y,ref)(y(2)-ref),'ref',0.0);
dae_opt = struct('load_model','cz_p_cz_q','vcon',vcon);
dae = stability.composite_dae(c, devices, dae_opt);
fprintf('nx=%d nb=%d ny_full=%d\n', numel(dae.x0), dae.nb, numel(dae.y0));
x0 = dae.x0; y0 = dae.y0;
y_full_init = y0; y_full_init(2) = 0.0;
free_vars = setdiff(1:numel(y0), 2, 'stable');
y_free_init = y_full_init(free_vars);
z0 = [x0(:); y_free_init(:)];
Ynet = dae.Ynet; u = dae.u0; V1_imag_ref = 0.0;
residual_fn = @(z) eq_residual(z, numel(x0), free_vars, 2, V1_imag_ref, numel(y0), dae, Ynet, u);
r0 = residual_fn(z0);
fprintf('initial residual norm=%.3e (nx+ny_free=%d, residual len=%d)\n', norm(r0,inf), numel(z0), numel(r0));
% Check f and g separately
f0 = dae.dae_f(0, x0, y_full_init, u, struct());
g0 = dae.dae_g(0, x0, y_full_init, Ynet, u, struct());
fprintf('f norm=%.3e (len=%d), g norm=%.3e (len=%d)\n', norm(f0,inf), numel(f0), norm(g0,inf), numel(g0));
% FD Jacobian and rank
fd_eps = 3e-6;
nz = numel(z0); J = zeros(nz,nz);
for j=1:nz
    zp=z0; zp(j)=zp(j)+fd_eps; J(:,j)=(residual_fn(zp)-r0)/fd_eps;
end
fprintf('J size=%dx%d, rcond=%.3e\n', size(J,1), size(J,2), rcond(J));
% count zero-ish columns (state vars with no residual coupling)
colnorms = sum(abs(J),1);
fprintf('zero-ish Jacobian columns (|col|<1e-12): %d\n', sum(colnorms<1e-12));
fprintf('col norms min=%.3e max=%.3e\n', min(colnorms), max(colnorms));
% Show device state_names to understand SG1 angle reference
fprintf('SG1 state_names: '); fprintf('%s ', dae.devices(1).state_names{:}); fprintf('\n');

function r = eq_residual(z, nx, free_vars, vcon_vars, vcon_ref, ny_full, dae, Y, u)
x = z(1:nx); y_free = z(nx+1:end);
y_full = zeros(ny_full,1); y_full(vcon_vars) = vcon_ref; y_full(free_vars) = y_free;
ec = struct();
f = dae.dae_f(0,x,y_full,u,ec); g = dae.dae_g(0,x,y_full,Y,u,ec);
free_rows = setdiff(1:numel(g), dae.vcon.rows, 'stable');
r = [f(:); g(free_rows)];
end
