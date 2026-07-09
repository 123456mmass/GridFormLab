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
r = stability.kundur_ex126_book_flux_ssa();
V = r.init.Vd.*r.init.Id + r.init.Vq.*r.init.Iq;
Ra_sys = cases.kundur_ex126_book_case().machines.reactances.Ra*(100/900);
Te = V + Ra_sys*(r.init.Id.^2+r.init.Iq.^2);
verifyLessThan(testCase,max(abs(r.init.Tm-Te)),1e-10);
end
