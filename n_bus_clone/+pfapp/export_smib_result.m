function app = export_smib_result(app, output_dir)
%EXPORT_SMIB_RESULT Write the SMIB eigenvalue table + plots to disk.
%   Saves a CSV eigenvalue table and PNGs of the s-plane and impulse
%   response figures currently rendered in the SMIB Stability tab.

if ~exist(output_dir, 'dir'); mkdir(output_dir); end

s = app.last_smib;
r = s.analyze;
lam = r.eigenvalues;
prefix = pfapp.make_safe_name(sprintf('SMIB_Model_%s', s.model));

% Eigenvalue CSV
eig_str = arrayfun(@(z) sprintf('%.6f%+.6fj', real(z), imag(z)), lam, ...
    'UniformOutput', false);
tbl = table(eig_str, real(lam), imag(lam), r.damping, r.freq_Hz, ...
    'VariableNames', {'eigenvalue', 'sigma', 'omega', 'zeta', 'freq_Hz'});
csv_path = fullfile(output_dir, [prefix '_eigenvalues.csv']);
writetable(tbl, csv_path);

% Figures (export the in-GUI axes, fall back to standalone figures if absent)
pngs = {};
try
    plane_path = fullfile(output_dir, [prefix '_splane.png']);
    exportgraphics(app.ax_smib_plane, plane_path, 'Resolution', 150);
    pngs{end+1} = plane_path; %#ok<AGROW>
catch
end
try
    step_path = fullfile(output_dir, [prefix '_step_response.png']);
    exportgraphics(app.ax_smib_step, step_path, 'Resolution', 150);
    pngs{end+1} = step_path; %#ok<AGROW>
catch
end

pfapp.append_log(app, sprintf('Exported SMIB: %s', csv_path));
for k = 1:numel(pngs)
    pfapp.append_log(app, sprintf('  figure: %s', pngs{k}));
end
end
