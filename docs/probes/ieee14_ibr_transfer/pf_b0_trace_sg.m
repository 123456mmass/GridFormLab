function pf_b0_trace_sg()
%PF_B0_TRACE_SG  Trace which SG1 differential equation produces NaN (temporary).
%   STATUS: DIAGNOSTIC/WIP. Unreachable from production. Preserved for root-cause
%   evidence of Tpq0=0 singular-limit NaN.
%   See: docs/project/handoffs/IEEE14_GENERIC_IBR_MACHINE_TRANSFER.md
%
%   Line 59: dx4 = (c_q*Edpp - d_q*Edp) / Tpq0 = 0/0 = NaN when Tpq0=0.
cd('/home/birds/Documents/Power-flow');
path(path, pwd); pf_init_paths;
rehash; clear functions; clear classes;
rehash; rehash path; rehash toolbox;

c = cases.case_ieee14_1sg_4ibr_auto_vsg();
disp_struct = struct('IBR2',40.0,'IBR3',0.0,'IBR6',0.0,'IBR8',0.0);
modes = struct('device_id',{'IBR2','IBR3','IBR6','IBR8'},'mode',{'gfl','gfl','gfl','gfl'});
[devices, ~] = ibr.build_ieee14_sg_ibr_devices(c, modes, disp_struct);

vcon = struct('vars',2,'rows',2,'eq',@(y,ref)(y(2)-ref),'ref',0.0);
dae_opt = struct('load_model','cz_p_cz_q','vcon',vcon);
dae = stability.composite_dae(c, devices, dae_opt);

x0 = dae.x0; y0 = dae.y0;
y_full = y0; y_full(2) = 0.0;

% SG1 state slice (device 1, nx=6)
sg = dae.devices(1);
off1 = dae.device_offsets(1);
xs = x0(off1+1:off1+sg.nx);
fprintf('SG1 x0 = [delta=%.6f omega=%.6f Eqp=%.6f Edp=%.6f Eqpp=%.6f Edpp=%.6f]\n', ...
    xs(1), xs(2), xs(3), xs(4), xs(5), xs(6));
fprintf('SG1 bus y: Re(V1)=%.6f Im(V1)=%.6g\n', y_full(1), y_full(2));

% Inspect the EMF6 machine struct + units (built inside sg_composite_device).
% Reconstruct via synchronous_emf6_ssa to get machine/units/init.
emf_opt = struct('fd_eps',3e-6,'equilibrium_tolerance',1e-10, ...
    'newton_max_iterations',300,'load_model','cz_p_cz_q');
emf = stability.synchronous_emf6_ssa(c, emf_opt);
machine = emf.machine; units = emf.units; init = emf.init;
fprintf('ng=%d  units.bus_idx=%d  units.H_system(1)=%.6f  units.D_system(1)=%.6f\n', ...
    machine.ng, units.bus_idx(1), units.H_system(1), units.D_system(1));
fprintf('machine.w0=%.6f  Ra(1)=%.6f  Xdpp(1)=%.6f  Xqpp(1)=%.6f\n', ...
    machine.w0, machine.Ra(1), machine.Xdpp(1), machine.Xqpp(1));
fprintf('machine.Tpd0(1)=%.6f Tppd0(1)=%.6f Tpq0(1)=%.6f Tppq0(1)=%.6f\n', ...
    machine.Tpd0(1), machine.Tppd0(1), machine.Tpq0(1), machine.Tppq0(1));
fprintf('init.x0(1:6) = [%.6f %.6f %.6f %.6f %.6f %.6f]\n', init.x0(1:6));
fprintf('init.Tm(1)=%.6f  init.Efd(1)=%.6f\n', init.Tm(1), init.Efd(1));

% Now replicate sg_f online branch step by step.
bp = 1; k = 1;
delta = xs(1); w = xs(2);
Eqp = xs(3); Edp = xs(4); Eqpp = xs(5); Edpp = xs(6);
V = complex(y_full(2*bp-1), y_full(2*bp));
[Vd, Vq] = stability.kundur_book_dq(V, delta);
rhs_d = Vd - Edpp;
rhs_q = Vq - Eqpp;
det = machine.Xdpp(k)*machine.Xqpp(k) + machine.Ra(k)^2;
Id = (-machine.Ra(k)*rhs_d - machine.Xqpp(k)*rhs_q) / det;
Iq = ( machine.Xdpp(k)*rhs_d - machine.Ra(k)*rhs_q) / det;
Te = Vd*Id + Vq*Iq + machine.Ra(k)*(Id^2 + Iq^2);
fprintf('Vd=%.6f Vq=%.6f  Id=%.6f Iq=%.6f  Te=%.6f  det=%.6e\n', Vd, Vq, Id, Iq, Te, det);
dx1 = machine.w0 * w;
dx2 = (init.Tm(1) - Te - units.D_system(k)*w) / (2*units.H_system(k));
dx3 = (init.Efd(1) + machine.c_d(k)*Eqpp - machine.d_d(k)*Eqp) / machine.Tpd0(k);
dx4 = (machine.c_q(k)*Edpp - machine.d_q(k)*Edp) / machine.Tpq0(k);
dx5 = (Eqp - Eqpp - (machine.Xdp(k) - machine.Xdpp(k))*Id) / machine.Tppd0(k);
dx6 = (Edp - Edpp + (machine.Xqp(k) - machine.Xqpp(k))*Iq) / machine.Tppq0(k);
fprintf('dx1=%.6f dx2=%.6f dx3=%.6f dx4=%.6f dx5=%.6f dx6=%.6f\n', dx1,dx2,dx3,dx4,dx5,dx6);
fprintf('machine.c_d(1)=%.6f d_d(1)=%.6f c_q(1)=%.6f d_q(1)=%.6f\n', ...
    machine.c_d(1), machine.d_d(1), machine.c_q(1), machine.d_q(1));
fprintf('machine.Xdp(1)=%.6f Xqp(1)=%.6f\n', machine.Xdp(1), machine.Xqp(1));
end
