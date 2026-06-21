function result = kundur_ex126_classical_analysis()
%KUNDUR_EX126_CLASSICAL_ANALYSIS Classical/manual-excitation modes for Kundur Ex. 12.6.
%   In-house benchmark data object for the manually excited four-machine,
%   two-area system in Kundur Example 12.6. The values are used by the GUI
%   demonstration/report generator to compare the project implementation
%   against Table E12.3 in the book.
%
%   No MATLAB power-system toolbox is used. Frequency and damping ratio are
%   computed directly from the eigenvalues by
%       f = abs(imag(lambda))/(2*pi)
%       zeta = -real(lambda)/abs(lambda)

result = struct();
result.system_name = 'Kundur Example 12.6 - Two-Area Four-Machine Classical/Manual Excitation';
result.reference = 'Kundur Table E12.3';

% Condensed physically important modes from Table E12.3.
% Real/imaginary values are the eigenvalues printed in the book. Frequency
% and damping are recomputed below by this implementation.
rows = struct( ...
    'mode', {}, 'lambda', {}, 'book_frequency_Hz', {}, 'book_zeta', {}, ...
    'dominant_states', {}, 'mode_type', {});

rows(end+1) = make_row('Interarea rotor-angle mode', -0.111 + 1i*3.43, 0.545, 0.032, ...
    'Delta omega/delta G1,G2 vs G3,G4', 'interarea');
rows(end+1) = make_row('Area 1 local rotor-angle mode', -0.492 + 1i*6.82, 1.087, 0.072, ...
    'Delta omega/delta G1 vs G2', 'local-area-1');
rows(end+1) = make_row('Area 2 local rotor-angle mode', -0.506 + 1i*7.02, 1.117, 0.072, ...
    'Delta omega/delta G3 vs G4', 'local-area-2');

for k = 1:numel(rows)
    lam = rows(k).lambda;
    rows(k).computed_frequency_Hz = abs(imag(lam)) / (2*pi);
    rows(k).computed_zeta = -real(lam) / abs(lam);
    rows(k).frequency_error_Hz = rows(k).computed_frequency_Hz - rows(k).book_frequency_Hz;
    rows(k).zeta_error = rows(k).computed_zeta - rows(k).book_zeta;
end

result.modes = rows;

% Full Table E12.3 values for report reproduction.
result.full_table = {
    '1,2',   '-0.76E-3', '+/-0.22E-2', '0.0003', '0.331', 'Delta omega and Delta delta of G1, G2, G3, G4';
    '3',     '-0.96E-1', '-',          '-',      '-',     'same';
    '4,5',   '-0.111',   '+/-3.43',    '0.545',  '0.032', 'same';
    '6',     '-0.117',   '-',          '-',      '-',     'same';
    '7',     '-0.265',   '-',          '-',      '-',     'Delta field-flux linkage of G3 and G4';
    '8',     '-0.276',   '-',          '-',      '-',     'Delta field-flux linkage of G1 and G2';
    '9,10',  '-0.492',   '+/-6.82',    '1.087',  '0.072', 'Delta omega and Delta delta of G1 and G2';
    '11,12', '-0.506',   '+/-7.02',    '1.117',  '0.072', 'Delta omega and Delta delta of G3 and G4';
    '13',    '-3.428',   '-',          '-',      '-',     'd and q axis damper flux linkages';
    '14',    '-4.139',   '-',          '-',      '-',     'd and q axis damper flux linkages';
    '15',    '-5.287',   '-',          '-',      '-',     'd and q axis damper flux linkages';
    '16',    '-5.303',   '-',          '-',      '-',     'd and q axis damper flux linkages';
    '17',    '-31.03',   '-',          '-',      '-',     'd and q axis damper flux linkages';
    '18',    '-32.45',   '-',          '-',      '-',     'd and q axis damper flux linkages';
    '19',    '-34.07',   '-',          '-',      '-',     'd and q axis damper flux linkages';
    '20',    '-35.53',   '-',          '-',      '-',     'd and q axis damper flux linkages';
    '21,22', '-37.89',   '+/-0.142',   '0.023',  '~1.0',  'd and q axis damper flux linkages';
    '23,24', '-38.01',   '+/-0.38E-1', '0.006',  '~1.0',  'd and q axis damper flux linkages'};

% Normalized illustrative speed mode-shape phasors matching Figure E12.10.
result.mode_shapes = struct();
result.mode_shapes.interarea = [1.0*exp(1i*pi), 0.92*exp(1i*pi), 0.95, 1.0];
result.mode_shapes.area1 = [1.0*exp(1i*pi), 1.0, 0.08, 0.06];
result.mode_shapes.area2 = [0.06, 0.08, 1.0*exp(1i*pi), 1.0];
result.generator_labels = {'G1','G2','G3','G4'};
end

function row = make_row(mode, lambda, book_frequency_Hz, book_zeta, dominant_states, mode_type)
row = struct();
row.mode = mode;
row.lambda = lambda;
row.book_frequency_Hz = book_frequency_Hz;
row.book_zeta = book_zeta;
row.dominant_states = dominant_states;
row.mode_type = mode_type;
end
