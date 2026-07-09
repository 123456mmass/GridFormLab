function tests = test_kundur_literature_ranges()
%TEST_KUNDUR_LITERATURE_RANGES Cross-check against independent literature/tool ranges.
%
% These tests are intentionally range-based, not exact-golden-value tests.
% They guard against overfitting the scanned Kundur Table E12.3 wrapper by
% checking that the stated-parameter modern GENTPJ path remains consistent
% with independently reproduced Kundur two-area results reported by:
%   - MathWorks/OPAL-RT Kundur two-area PSS example: local modes near
%     1.12 Hz and 1.16 Hz with zeta around 0.08.
%   - Academia.edu paper "Factors affecting Small Signal Stability in Two
%     Area System": local modes around 1.09 Hz and 1.13 Hz with damping
%     around 0.08--0.085, and an inter-area mode around 0.55--0.57 Hz.
%   - colib.net / IEEE PES-TR18 as benchmark system-definition references.

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function test_modern_gentpj_matches_independent_literature_ranges(testCase)
    ssa = stability.kundur_ex126_kundur_ssa('options', struct('load_model','cc_p_cz_q'));
    modes = local_rotor_modes(ssa.eigenvalues);
    freq = imag(modes) / (2*pi);
    zeta = -real(modes) ./ abs(modes);

    % Independent reproduced tools/papers cluster in these bands.  The bands
    % are deliberately wider than the numerical regression tests because the
    % cited sources use different software implementations and controls.
    testCase.verifyGreaterThan(freq(1), 0.53, 'Interarea frequency too low');
    testCase.verifyLessThan(   freq(1), 0.58, 'Interarea frequency too high');
    testCase.verifyGreaterThan(zeta(1), 0.030, 'Interarea damping too low');
    testCase.verifyLessThan(   zeta(1), 0.042, 'Interarea damping too high');

    testCase.verifyGreaterThan(freq(2), 1.06, 'Area-1 local frequency too low');
    testCase.verifyLessThan(   freq(2), 1.13, 'Area-1 local frequency too high');
    testCase.verifyGreaterThan(zeta(2), 0.075, 'Area-1 local damping too low');
    testCase.verifyLessThan(   zeta(2), 0.090, 'Area-1 local damping too high');

    testCase.verifyGreaterThan(freq(3), 1.09, 'Area-2 local frequency too low');
    testCase.verifyLessThan(   freq(3), 1.17, 'Area-2 local frequency too high');
    testCase.verifyGreaterThan(zeta(3), 0.075, 'Area-2 local damping too low');
    testCase.verifyLessThan(   zeta(3), 0.090, 'Area-2 local damping too high');
end

function modes = local_rotor_modes(lambda)
    osc = lambda(abs(imag(lambda)) > 0.1 & real(lambda) < 0 & imag(lambda) > 0);
    [~, idx] = sort(abs(imag(osc)));
    osc = osc(idx);
    if numel(osc) < 3
        error('test_kundur_literature_ranges:notEnoughModes', 'Expected at least three rotor modes.');
    end
    modes = osc(1:3);
end
