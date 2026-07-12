function tests = test_ts_algebraic_ordering()
%TEST_TS_ALGEBRAIC_ORDERING  Interleaved y order contract (plan §8).
%   Verifies the algebraic state y = [Re(V1),Im(V1),...,Re(Vnb),Im(Vnb)]^T for
%   Padiyar and EMF6 against the runtime code.
tests = functiontests(localfunctions);
end
function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end
function test_emf6_y_interleaved(testCase)
c = cases.case_kundur_two_area_classical();
opt = struct('load_model','cz','fault_bus',8,'t_fault',1.0,'t_clear',1.05,'Zf',1i*0.1);
dae = stability.emf6_dae(c, opt);
y0 = dae.init.y0(:); nb = dae.nb;
% Reconstruct V from y0 interleaved and compare to PF voltages.
V_from_y = complex(y0(1:2:2*nb), y0(2:2:2*nb));
pf = dae.pf;
V_pf = pf.bus_voltage(:).*exp(1i*deg2rad(pf.bus_angle_deg(:)));
testCase.verifyEqual(V_from_y, V_pf, 'AbsTol', 1e-10, ...
    'EMF6 y must be interleaved [Re(V1),Im(V1),...].');
end
function test_padiyar_y_interleaved(testCase)
c = cases.case_padiyar_two_area_4m_avr();
opt = struct('excitation','avr','fault_bus',3,'fault_enabled',false);
dae = stability.padiyar_model11_dae(c, opt);
y0 = dae.y0(:); nb = dae.nb;
V_from_y = complex(y0(1:2:2*nb), y0(2:2:2*nb));
pf = dae.pf;
V_pf = pf.bus_voltage(:).*exp(1i*deg2rad(pf.bus_angle_deg(:)));
testCase.verifyEqual(V_from_y, V_pf, 'AbsTol', 1e-10, ...
    'Padiyar y must be interleaved [Re(V1),Im(V1),...].');
end
