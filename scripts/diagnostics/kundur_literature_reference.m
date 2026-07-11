function info = kundur_literature_reference()
%KUNDUR_LITERATURE_REFERENCE  Diagnostic-only collection of INDEPENDENTLY
%   reproduced Kundur two-area oscillatory-mode ranges from other tools/papers.
%
%   THIS IS DIAGNOSTIC ONLY. It is NOT a pass/fail target, NOT part of the
%   regression suite, and NOT an acceptance criterion. The in-house EMF6
%   model is validated by physics/model-contract tests
%   (test_emf6_physics_contract) and cross-validation (PSAT/PGAz), never by
%   matching these literature numbers.
%
%   Sources (independent reproductions, NOT Kundur Table E12.3):
%     - MathWorks/OPAL-RT Kundur two-area PSS example: local modes ~1.12/1.16 Hz, zeta~0.08.
%     - "Factors affecting Small Signal Stability in Two Area System": local ~1.09/1.13 Hz,
%       zeta~0.08-0.085; inter-area ~0.55-0.57 Hz.
%     - IEEE PES-TR18 / colib.net as benchmark system-definition references.
%
%   These ranges are reported here for STUDY only. Run as a script to print
%   the in-house EMF6 modes alongside them for qualitative comparison.

info = struct();
info.interarea_freq_Hz = [0.53 0.58];
info.interarea_zeta     = [0.030 0.042];
info.local_area1_freq_Hz = [1.06 1.13];
info.local_area1_zeta   = [0.075 0.090];
info.local_area2_freq_Hz = [1.09 1.17];
info.local_area2_zeta   = [0.075 0.090];
info.note = 'DIAGNOSTIC ONLY — not a pass/fail target, not an acceptance criterion.';

if nargout == 0
    fprintf('=== Kundur two-area literature ranges (DIAGNOSTIC ONLY) ===\n');
    fprintf('Inter-area: freq %.2f-%.2f Hz, zeta %.3f-%.3f\n', info.interarea_freq_Hz, info.interarea_zeta);
    fprintf('Area-1 local: freq %.2f-%.2f Hz, zeta %.3f-%.3f\n', info.local_area1_freq_Hz, info.local_area1_zeta);
    fprintf('Area-2 local: freq %.2f-%.2f Hz, zeta %.3f-%.3f\n', info.local_area2_freq_Hz, info.local_area2_zeta);
    fprintf('%s\n', info.note);
end
end
