function manifest = report_manifest(report_head, outdir, entries)
%REPORT_MANIFEST  Build and write the machine-readable report manifest.
%   MANIFEST = report_manifest(REPORT_HEAD, OUTDIR, ENTRIES) assembles the
%   manifest struct and writes it to OUTDIR/manifest.json and OUTDIR/manifest.mat.
%
%   Manifest fields (mission requirement):
%     git_head, timestamp, timezone, matlab_version, entry_point,
%     cases: [ {case_function, solver_model_stepper, source_reference_status,
%               fresh_saved_status, input_contract_fingerprint, output_filenames} ]
%
%   REPORT_HEAD is the Git HEAD commit hash. ENTRIES is a struct array of
%   per-case records built by the generator.

manifest = struct();
manifest.git_head = report_head;
manifest.timestamp = char(datetime('now','Format','yyyy-MM-dd HH:mm:ss'));
manifest.timezone = char(datetime('now','TimeZone','local','Format','Z'));
manifest.matlab_version = version;
manifest.entry_point = 'generate_system_methods_report';
manifest.origin_main = '';
try
    [status, origin_main] = system('git -C /home/birds/Documents/Power-flow-report rev-parse origin/main');
    if status == 0, manifest.origin_main = strtrim(origin_main); end
catch
end
manifest.cases = entries;

% Write JSON (if jsonencode available) and .mat.
try
    json = jsonencode(manifest, 'PrettyPrint', true);
    fid = fopen(fullfile(outdir,'manifest.json'),'w');
    z = onCleanup(@()fclose(fid)); %#ok<NASGU>
    fprintf(fid, '%s', json);
catch
end
save(fullfile(outdir,'manifest.mat'), 'manifest');
end
