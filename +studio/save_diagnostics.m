function files = save_diagnostics(result, outdir, analysis)
%SAVE_DIAGNOSTICS  Write result diagnostics (CSV) to OUTDIR on request.
%   files = studio.save_diagnostics(result, outdir, analysis) writes one CSV
%   per available numeric product and returns the file paths:
%     PF   -> pf_bus_results.csv   (bus id, V pu, angle deg)
%     SSSA -> sssa_eigenvalues.csv (real, imag, f Hz, zeta)
%     TS   -> ts_samples.csv       (t, min |V|, max |dw|)
%
%   This is an EXPLICIT user action (Save Diagnostics).  It is never invoked
%   by run_analysis or by a run button; the GUI calls it only when
%   opt.save_diagnostics is set.  No figure, no diary, no PNG is written.
%
%   See also: studio.RUN_ANALYSIS.

if nargin < 3 || isempty(analysis), analysis = ''; end
if ~exist(outdir, 'dir'), mkdir(outdir); end
files = {};

analysis = lower(char(analysis));

if isempty(analysis) || strcmp(analysis, 'pf')
    if isstruct(result) && isfield(result, 'bus_voltage') && ...
            isfield(result, 'bus_angle_deg')
        f = fullfile(outdir, 'pf_bus_results.csv');
        v = result.bus_voltage(:); a = result.bus_angle_deg(:);
        if isfield(result, 'external_bus_ids')
            ids = result.external_bus_ids(:);
        else
            ids = (1:numel(v)).';
        end
        fid = fopen(f, 'w');
        if fid < 0
            error('studio:save_diagnostics:openFailed', 'Cannot write %s.', f);
        end
        fprintf(fid, 'bus_id,voltage_pu,angle_deg\n');
        for k = 1:numel(v)
            fprintf(fid, '%d,%.10g,%.10g\n', ids(k), v(k), a(k));
        end
        fclose(fid);
        files{end+1} = f; %#ok<AGROW>
    end
end

if isempty(analysis) || strcmp(analysis, 'sssa')
    lam = [];
    if isstruct(result) && isfield(result, 'eigenvalues')
        lam = result.eigenvalues(:);
    elseif isstruct(result) && isfield(result, 'reduced_eigenvalues') && ...
            ~isempty(result.reduced_eigenvalues)
        lam = result.reduced_eigenvalues(:);
    end
    if ~isempty(lam)
        f = fullfile(outdir, 'sssa_eigenvalues.csv');
        fid = fopen(f, 'w');
        if fid < 0
            error('studio:save_diagnostics:openFailed', 'Cannot write %s.', f);
        end
        fprintf(fid, 'real_per_s,imag_per_s,f_hz,zeta\n');
        for k = 1:numel(lam)
            re_k = real(lam(k)); im_k = imag(lam(k));
            fprintf(fid, '%.10g,%.10g,%.10g,%.10g\n', re_k, im_k, ...
                abs(im_k) / (2 * pi), -re_k / (abs(lam(k)) + eps));
        end
        fclose(fid);
        files{end+1} = f; %#ok<AGROW>
    end
end

if isempty(analysis) || strcmp(analysis, 'ts')
    if isstruct(result) && isfield(result, 't') && isfield(result, 'Vbus')
        f = fullfile(outdir, 'ts_samples.csv');
        t = result.t(:);
        nt = numel(t);
        step = max(1, ceil(nt / 500));   % downsample long runs
        sel = 1:step:nt;
        fid = fopen(f, 'w');
        if fid < 0
            error('studio:save_diagnostics:openFailed', 'Cannot write %s.', f);
        end
        fprintf(fid, 't_s,min_vbus_pu,max_abs_dw_pu\n');
        % ts_simulate stores time along dim 1: Vbus is [nt x nb], omega [nt x ng].
        for k = sel
            vk = result.Vbus(k, :);
            dw_k = NaN;
            if isfield(result, 'omega') && ~isempty(result.omega)
                if isfield(result, 'omega_is_deviation') && result.omega_is_deviation
                    dw_k = max(abs(result.omega(k, :)));
                else
                    dw_k = max(abs(result.omega(k, :) - 1));
                end
            end
            fprintf(fid, '%.10g,%.10g,%.10g\n', t(k), min(vk), dw_k);
        end
        fclose(fid);
        files{end+1} = f; %#ok<AGROW>
    end
end
end
