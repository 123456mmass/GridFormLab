function tests = test_sauer_pai_reference_catalog()
%TEST_SAUER_PAI_REFERENCE_CATALOG Published non-Kundur dynamic benchmark catalog.
% Locks the published Sauer-Pai Example 8.3 / Table 8.2 eigenvalue targets.

tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(fileparts(fileparts(mfilename('fullpath'))));
    pf_init_paths();
end

function test_sauer_pai_example_8_3_targets_are_available(testCase)
    catalog = cases.sauer_pai_reference_catalog();
    ex = catalog.example_8_3_table_8_1;

    testCase.verifyEqual(numel(ex.eigenvalues), 21, ...
        'Sauer-Pai Example 8.3 should provide 21 eigenvalues');

    % Key published targets from Table 8.2 (corrected real/complex assignment).
    expected = [
        -0.7209 + 1i*12.7486;
        -0.1908 + 1i*8.3672;
        -5.4875 + 1i*7.9487;
        -3.3995 + 0i;           % real eigenvalue (Table 8.2)
        -0.4445 + 1i*1.2104;    % complex pair (Table 8.2)
        -0.4260 + 1i*0.4960];   % complex pair (Table 8.2)
    for k = 1:numel(expected)
        testCase.verifyTrue(any(abs(ex.eigenvalues - expected(k)) < 1e-10), ...
            sprintf('Missing Sauer-Pai published eigenvalue %g%+gj', real(expected(k)), imag(expected(k))));
    end

    zero_modes = ex.eigenvalues(abs(ex.eigenvalues) < 1e-12);
    testCase.verifyEqual(numel(zero_modes), 2, ...
        'Sauer-Pai Example 8.3 has two zero eigenvalues for D_i=0');
end

function test_sauer_pai_example_8_3_damping_frequency_targets(testCase)
    ex = cases.sauer_pai_reference_catalog().example_8_3_table_8_1;
    osc = ex.eigenvalues(abs(imag(ex.eigenvalues)) > 1e-6 & imag(ex.eigenvalues) > 0);
    [~, idx] = sort(abs(imag(osc)), 'descend');
    osc = osc(idx);

    freq = imag(osc) / (2*pi);
    zeta = -real(osc) ./ abs(osc);

    % Spot-check computed frequency/damping from the published eigenvalues.
    testCase.verifyEqual(freq(1), 12.7486/(2*pi), 'AbsTol', 1e-10);
    testCase.verifyEqual(zeta(1), 0.7209/hypot(0.7209,12.7486), 'AbsTol', 1e-10);
    % Lowest frequency mode is -0.4260 +/- j0.4960 (Table 8.2).
    testCase.verifyEqual(freq(end), 0.4960/(2*pi), 'AbsTol', 1e-10);
    testCase.verifyEqual(zeta(end), 0.4260/hypot(0.4260,0.4960), 'AbsTol', 1e-10);
end
