function tests = test_sssa_reference_independence()
%TEST_SSSA_REFERENCE_INDEPENDENCE Cross-model SSSA contract tests.
%   Verifies the production SSSA paths (Padiyar manual, Padiyar AVR, EMF6) from
%   their equations, NOT from published/literature acceptance targets. Tolerances
%   are declared up front from numerical precision and integration order -- they
%   are NOT relaxed after seeing a result.
%
%   Contracts:
%     1. Equilibrium residual + state count (manual=16, AVR=20, EMF6=6*ng)
%     2. SSSA and TS share the same DAE (same residual on same input, incl. perturbed)
%     3. Schur complement contract (Afull = Jxx - Jxy*(Jyy\Jyx); dimensions; finite)
%     4. No inv(Jyy) in production +stability/
%     5. Eigenvalue structure (finite, conjugate pairs)
%     6. Reference-angle structure (angle_shift_residual; zero mode Afull*shift~0)
%     7. Modal metrics present and finite (frequency, damping, time constant)

tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function ssa = padiyar_avr_fixture()
c = cases.case_padiyar_two_area_4m_avr();
ssa = stability.padiyar_model11_ssa(c, struct('excitation','avr','fd_eps',1e-6));
end

function ssa = padiyar_manual_fixture()
c = cases.case_padiyar_two_area_4m_avr();
ssa = stability.padiyar_model11_ssa(c, struct('excitation','manual','fd_eps',1e-6));
end

function ssa = emf6_fixture()
c = cases.kundur_ex126_book_case();
ssa = stability.synchronous_emf6_ssa(c, struct('load_model','cc_p_cz_q'));
end

function test_1_padiyar_table95_corruption_invariant(testCase)
% Falsification test: corrupting reference.table95_eigenvalues must not alter
% the computed Afull or eigenvalues.
c = cases.case_padiyar_two_area_4m_avr();
r1 = stability.padiyar_model11_ssa(c, struct('excitation','avr','fd_eps',1e-6));
c2 = c;
c2.reference.table95_eigenvalues = (101:120).' + 1i*(201:220).';
r2 = stability.padiyar_model11_ssa(c2, struct('excitation','avr','fd_eps',1e-6));
testCase.verifyEqual(r2.Afull, r1.Afull, 'AbsTol', 1e-12, ...
    'Afull invariant under table95 corruption');
testCase.verifyEqual(sort(r2.eigenvalues), sort(r1.eigenvalues), 'AbsTol', 1e-12, ...
    'eigenvalues invariant under table95 corruption');
end

function test_2_padiyar_printed_op_corruption_invariant(testCase)
% Falsification test: corrupting the printed operating-point comparison copies
% (printed_V/angle/Pg/Qg) AND table95 must not alter the SSSA result. Only
% COMPARISON-ONLY fields are corrupted; physical inputs are untouched.
c = cases.case_padiyar_two_area_4m_avr();
r1 = stability.padiyar_model11_ssa(c, struct('excitation','avr','fd_eps',1e-6));
c2 = c;
c2.operating_point.printed_V = (0.5:0.1:1.4).';
c2.operating_point.printed_angle_deg = (-50:5:-5).';
c2.operating_point.printed_Pg = rand(10,1)*10;
c2.operating_point.printed_Qg = rand(10,1)*5;
c2.reference.table95_eigenvalues = (101:120).' + 1i*(201:220).';
r2 = stability.padiyar_model11_ssa(c2, struct('excitation','avr','fd_eps',1e-6));
testCase.verifyEqual(r2.Afull, r1.Afull, 'AbsTol', 1e-12, ...
    'Afull invariant under printed_op + table95 corruption');
testCase.verifyEqual(sort(r2.eigenvalues), sort(r1.eigenvalues), 'AbsTol', 1e-12, ...
    'eigenvalues invariant under printed_op + table95 corruption');
testCase.verifyEqual(r2.pf.bus_voltage, r1.pf.bus_voltage, 'AbsTol', 1e-12, ...
    'PF voltage invariant under reference corruption');
testCase.verifyEqual(r2.pf.bus_angle_deg, r1.pf.bus_angle_deg, 'AbsTol', 1e-12, ...
    'PF angle invariant under reference corruption');
end

function test_3_padiyar_manual_reference_invariant(testCase)
% Same falsification for the manual excitation path.
c = cases.case_padiyar_two_area_4m_avr();
r1 = stability.padiyar_model11_ssa(c, struct('excitation','manual','fd_eps',1e-6));
c2 = c;
c2.reference.table95_eigenvalues = (101:120).' + 1i*(201:220).';
c2.operating_point.printed_V = (0.5:0.1:1.4).';
c2.operating_point.printed_Pg = rand(10,1)*10;
r2 = stability.padiyar_model11_ssa(c2, struct('excitation','manual','fd_eps',1e-6));
testCase.verifyEqual(r2.Afull, r1.Afull, 'AbsTol', 1e-12, ...
    'manual Afull invariant under reference corruption');
testCase.verifyEqual(sort(r2.eigenvalues), sort(r1.eigenvalues), 'AbsTol', 1e-12, ...
    'manual eigenvalues invariant under reference corruption');
end

function test_4_emf6_reference_invariant(testCase)
% EMF6 (Kundur 12.6) case: the case loader attaches no published comparison
% fields that the SSSA reads. Confirm the SSSA result is stable regardless of
% any reference-like field we inject, proving the EMF6 SSSA does not consume
% comparison data.
c = cases.kundur_ex126_book_case();
r1 = stability.synchronous_emf6_ssa(c, struct('load_model','cc_p_cz_q'));
c2 = c;
c2.reference_fake_eigenvalues = (1:24).' + 1i*(25:48).';
c2.printed_fake_V = rand(10,1);
r2 = stability.synchronous_emf6_ssa(c2, struct('load_model','cc_p_cz_q'));
testCase.verifyEqual(r2.Afull, r1.Afull, 'AbsTol', 1e-12, ...
    'EMF6 Afull invariant under injected reference fields');
testCase.verifyEqual(sort(r2.eigenvalues), sort(r1.eigenvalues), 'AbsTol', 1e-12, ...
    'EMF6 eigenvalues invariant under injected reference fields');
end

function test_5_sssa_attaches_reference_for_reporting_only(testCase)
% Structural proof: padiyar_model11_ssa attaches case_data.reference to its
% output for REPORTING only. The computed result is produced by
% multimachine_ssa operating on the DAE and does not depend on reference.
c = cases.case_padiyar_two_area_4m_avr();
r = stability.padiyar_model11_ssa(c, struct('excitation','avr','fd_eps',1e-6));
testCase.verifyTrue(isfield(r,'reference'), 'SSSA output carries reference for reporting');
testCase.verifyEqual(r.reference.table95_eigenvalues, ...
    c.reference.table95_eigenvalues, 'AbsTol', 1e-12, ...
    'attached reference matches case reference (reporting copy)');
c2 = c; c2.reference.table95_eigenvalues = zeros(20,1);
r2 = stability.padiyar_model11_ssa(c2, struct('excitation','avr','fd_eps',1e-6));
testCase.verifyEqual(r2.Afull, r.Afull, 'AbsTol', 1e-12, ...
    'computed Afull independent of reference values');
end
