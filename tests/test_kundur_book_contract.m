function tests = test_kundur_book_contract()
%TEST_KUNDUR_BOOK_CONTRACT Coordinate/base/power identities for book path.
tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function test_dq_roundtrip(testCase)
angles = linspace(-pi,pi,101).';
z = (0.3+0.01*(1:101).') + 1i*(-0.7+0.013*(1:101).');
[d,q] = stability.kundur_book_dq(z,angles);
z_back = stability.kundur_book_network_current(d,q,angles);
verifyLessThan(testCase,max(abs(z_back-z)),1e-13);
end

function test_base_conversion_once(testCase)
c = cases.kundur_ex126_book_case();
r = c.machines.reactances;
scale = c.base_values.S_base_MVA/c.machines.base.S_MVA;
verifyEqual(testCase,scale,100/900,'AbsTol',eps);
verifyEqual(testCase,r.Xd*scale,0.2,'AbsTol',eps);
verifyEqual(testCase,r.Xq*scale,1.7/9,'AbsTol',eps);
verifyEqual(testCase,r.Xl*scale,1/45,'AbsTol',eps);
verifyEqual(testCase,[c.machines.units.H]/scale,[58.5,58.5,55.575,55.575], ...
    'AbsTol',eps);
end

function test_stator_power_and_torque_identity(testCase)
% Torque/power identity for the operational EMF6 model:
%   Te = Vd*Id + Vq*Iq + Ra*(Id^2 + Iq^2)
% must equal the mechanical torque Tm held at initialization (constant-Tm
% operating point). Vd,Vq are recovered from the network phasor and the
% rotor angle via the Kundur dq transform.
c = cases.kundur_ex126_book_case();
r = stability.synchronous_emf6_ssa(c,struct('load_model','cc_p_cz_q'));
init = r.init;
Ra_sys = c.machines.reactances.Ra * (c.base_values.S_base_MVA/c.machines.base.S_MVA);
Te = zeros(init.ng,1);
for k=1:init.ng
    b = init.bus_idx(k);
    V = complex(init.y0(2*b-1), init.y0(2*b));
    delta = init.x0((k-1)*6+1);
    [Vd,Vq] = stability.kundur_book_dq(V, delta);
    Te(k) = Vd*init.Id(k) + Vq*init.Iq(k) + Ra_sys*(init.Id(k)^2 + init.Iq(k)^2);
end
verifyLessThan(testCase,max(abs(init.Tm-Te)),1e-10);
end
