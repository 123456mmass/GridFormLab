function tests = test_et_fcs_device_frequency_real
%TEST_ET_FCS_DEVICE_FREQUENCY_REAL  Active frequency on REAL NE39 devices.
%   The online rate must read each device's ACTIVE frequency variable, not the
%   finite difference of some bus angle.  These tests build the actual NE39
%   5-SG/5-IBR devices, solve the mixed equilibrium, and assert:
%     * SG frequency is the rotor SPEED state (perturbing delta does not move it,
%       perturbing omega does);
%     * GFL frequency is the PLL frequency (perturbing the PLL ANGLE does not
%       move it);
%     * SG RoCoF at equilibrium is the device's own active RHS (== 0);
%     * the base frequency comes from CASE_DATA (a 50 Hz base rates at 50);
%     * a GFM device reads its VSG omega.
tests = functiontests(localfunctions);
end

function setupOnce(tc)
p=path; tc.addTeardown(@()path(p));
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
sc = cases.scenario_ne39_5sg_5ibr(struct('study_capability',true));
devs = stability.build_mixed_resource_devices(sc.case_data, sc.resources, sc.scenario_opt);
eq = stability.mixed_equilibrium_solve(sc.case_data, struct('devices',devs), ...
    struct('verbose',false));
tc.assertTrue(eq.converged, eq.failure_reason);
% Offsets.
offs = zeros(1,numel(devs)); uoffs = offs;
xo=0; uo=0;
for k=1:numel(devs)
    offs(k)=xo; uoffs(k)=uo; xo=xo+devs(k).nx; uo=uo+devs(k).nu;
end
% A GFM variant: rebuild with IBR30 starting grid-forming.
sc2 = cases.scenario_ne39_5sg_5ibr(struct('study_capability',true, ...
    'initial_modes',struct('device_id','IBR30','mode','gfm')));
gi = find(strcmp({sc2.resources.resource_id},'IBR30'),1);
devs2 = stability.build_mixed_resource_devices(sc2.case_data,sc2.resources,sc2.scenario_opt);
eq2 = stability.mixed_equilibrium_solve(sc2.case_data, struct('devices',devs2), ...
    struct('verbose',false));
tc.assertTrue(eq2.converged,eq2.failure_reason);
tc.TestData.sc = sc; tc.TestData.devs = devs; tc.TestData.eq = eq;
tc.TestData.offs = offs; tc.TestData.uoffs = uoffs;
tc.TestData.devs2 = devs2; tc.TestData.eq2 = eq2; tc.TestData.gi = gi;
end

function test_sg_frequency_is_speed_state_not_angle_fd(tc)
sc=tc.TestData.sc; devs=tc.TestData.devs; eq=tc.TestData.eq;
o=tc.TestData.offs; uo=tc.TestData.uoffs;
k=1; d=devs(k); x=eq.x0(o(k)+(1:d.nx)); u=eq.u_eq(uo(k)+(1:d.nu));
f0=stability.et_fcs_device_frequency(d,0,x,eq.y0,u,eq.equilibrium_context,sc.case_data);
tc.verifyEqual(f0.source,'sg_omega');
tc.verifyEqual(f0.f_hz,60,'AbsTol',1e-9);
% Perturb delta only: frequency must NOT move (it is not an angle difference).
x2=x; x2(1)=x(1)+0.1;
f2=stability.et_fcs_device_frequency(d,0,x2,eq.y0,u,eq.equilibrium_context,sc.case_data);
tc.verifyEqual(f2.f_hz,f0.f_hz,'AbsTol',1e-12);
% Perturb omega: frequency scales by the base.
x3=x; x3(2)=1.01;
f3=stability.et_fcs_device_frequency(d,0,x3,eq.y0,u,eq.equilibrium_context,sc.case_data);
tc.verifyEqual(f3.f_hz,60*1.01,'AbsTol',1e-9);
end

function test_gfl_frequency_is_pll(tc)
sc=tc.TestData.sc; devs=tc.TestData.devs; eq=tc.TestData.eq;
o=tc.TestData.offs; uo=tc.TestData.uoffs;
k=6; d=devs(k); x=eq.x0(o(k)+(1:d.nx)); u=eq.u_eq(uo(k)+(1:d.nu));
f0=stability.et_fcs_device_frequency(d,0,x,eq.y0,u,eq.equilibrium_context,sc.case_data);
tc.verifyEqual(f0.source,'gfl_pll');
rec=d.reconstruct(0,x,eq.y0,u,eq.equilibrium_context);
% The reported frequency IS the model's own PLL omega (with its controller
% terms folded in), not a finite difference of any angle.
tc.verifyEqual(f0.omega,rec.gfl.omega_PLL,'AbsTol',1e-12);
tc.verifyEqual(f0.f_hz,rec.gfl.omega_PLL/(2*pi),'AbsTol',1e-12);
tc.verifyEqual(f0.f_hz,f0.omega/(2*pi),'AbsTol',1e-12);
end

function test_sg_rocof_is_active_rhs(tc)
sc=tc.TestData.sc; devs=tc.TestData.devs; eq=tc.TestData.eq;
o=tc.TestData.offs; uo=tc.TestData.uoffs;
k=2; d=devs(k); x=eq.x0(o(k)+(1:d.nx)); u=eq.u_eq(uo(k)+(1:d.nu));
f=stability.et_fcs_device_frequency(d,0,x,eq.y0,u,eq.equilibrium_context,sc.case_data);
tc.verifyTrue(isfinite(f.fdot_hz_s));
tc.verifyEqual(f.fdot_hz_s,0,'AbsTol',1e-9);   % RHS is zero at equilibrium
end

function test_fbase_comes_from_case_not_hardcoded(tc)
devs=tc.TestData.devs; eq=tc.TestData.eq;
o=tc.TestData.offs; uo=tc.TestData.uoffs;
c50 = tc.TestData.sc.case_data; c50.base_values.frequency_Hz = 50;
k=1; d=devs(k); x=eq.x0(o(k)+(1:d.nx)); u=eq.u_eq(uo(k)+(1:d.nu));
f=stability.et_fcs_device_frequency(d,0,x,eq.y0,u,eq.equilibrium_context,c50);
tc.verifyEqual(f.f_hz,50,'AbsTol',1e-9);       % omega=1 -> 50 Hz, not 60
end

function test_reference_phase_jump_does_not_move_sg_frequency(tc)
% A global reference-phase jump rotates every bus voltage but must move no SG
% frequency: the speed state is unaffected by a wrapped angle reference.
sc=tc.TestData.sc; devs=tc.TestData.devs; eq=tc.TestData.eq;
o=tc.TestData.offs; uo=tc.TestData.uoffs;
k=3; d=devs(k); x=eq.x0(o(k)+(1:d.nx)); u=eq.u_eq(uo(k)+(1:d.nu));
f0=stability.et_fcs_device_frequency(d,0,x,eq.y0,u,eq.equilibrium_context,sc.case_data);
V=complex(eq.y0(1:2:end),eq.y0(2:2:end)); Vr=V*exp(1i*0.7);
y_rot=zeros(size(eq.y0)); y_rot(1:2:end)=real(Vr); y_rot(2:2:end)=imag(Vr);
f1=stability.et_fcs_device_frequency(d,0,x,y_rot,u,eq.equilibrium_context,sc.case_data);
tc.verifyEqual(f1.f_hz,f0.f_hz,'AbsTol',1e-12);
end

function test_gfm_reads_vsg_omega(tc)
sc=tc.TestData.sc; devs2=tc.TestData.devs2; eq2=tc.TestData.eq2;
tc.assertTrue(eq2.converged, eq2.failure_reason);
gi=tc.TestData.gi;
o=0; uo=0;
for k=1:gi-1, o=o+devs2(k).nx; uo=uo+devs2(k).nu; end
d=devs2(gi); x=eq2.x0(o+(1:d.nx)); u=eq2.u_eq(uo+(1:d.nu));
tc.verifyEqual(lower(string(d.mode)),"gfm");
f=stability.et_fcs_device_frequency(d,0,x,eq2.y0,u,eq2.equilibrium_context,sc.case_data);
tc.verifyEqual(f.source,'gfm_omega');
tc.verifyEqual(f.f_hz,60,'AbsTol',1e-6);
end
