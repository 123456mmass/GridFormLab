function tests=test_sg_prospective_close_metrics
tests=functiontests(localfunctions);
end

function setupOnce(tc)
root=fileparts(fileparts(mfilename('fullpath')));
addpath(root,'-begin'); tc.addTeardown(@() rmpath(root)); pf_init_paths();
end

function testIndependentPowerAndRatingOracle(tc)
dev=stub_device(0.20-0.10i);
ec=offline_context(); y=[1;0]; x=zeros(2,1); u=[0.25;1.0];
c=struct('base_values',struct('S_base_MVA',100), ...
    'machines',struct('base',struct('S_MVA',100)));
m=stability.sg_prospective_close_metrics(0,x,y,u,ec,dev,c);
tc.verifyEqual(m.I,0.20-0.10i,'AbsTol',0);
tc.verifyEqual(m.P_pu,0.20,'AbsTol',1e-15);
tc.verifyEqual(m.Q_pu,0.10,'AbsTol',1e-15);
tc.verifyEqual(m.torque_mismatch_pu,0.05,'AbsTol',1e-15);
tc.verifyEqual(m.current_limit_system_pu,1,'AbsTol',0);
tc.verifyTrue(m.passes);
tc.verifyFalse(ec.hybrid_state.device_online.SG1);
end

function testOverRatingFailsClosed(tc)
dev=stub_device(1.20);
c=struct('base_values',struct('S_base_MVA',100), ...
    'machines',struct('base',struct('S_MVA',100)));
m=stability.sg_prospective_close_metrics(0,zeros(2,1),[1;0],[0;1], ...
    offline_context(),dev,c);
tc.verifyFalse(m.current_pass);
tc.verifyFalse(m.passes);
end

function d=stub_device(I)
d=struct('device_id','SG1','bus_position',1, ...
    'current_injection',@(t,x,y,u,ec) current_if_online(I,ec), ...
    'electrical_power',@(t,x,y,u,ec) real(complex(y(1),y(2))*conj(current_if_online(I,ec))), ...
    'f',@(t,x,y,u,ec) zeros(size(x)), ...
    'reconstruct',@(t,x,y,u,ec) struct('V_open_circuit',complex(1,0)));
end

function I=current_if_online(value,ec)
if ec.hybrid_state.device_online.SG1, I=value; else, I=0; end
end

function ec=offline_context()
ec=struct('hybrid_state',struct( ...
    'device_online',struct('SG1',false), ...
    'device_modes',struct('SG1','breaker_open')));
end
