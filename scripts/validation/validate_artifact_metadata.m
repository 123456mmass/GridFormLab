function [ok, missing] = validate_artifact_metadata(a)
%VALIDATE_ARTIFACT_METADATA  Check that a validation artifact struct has all
%   required provenance/metadata fields (Mission H). Missing/empty field =>
%   ok=false and the field is listed in `missing`. Guards the bug where PSAT
%   entry points were mislabeled as PGAz functions and the source commit was
%   absent.
required = {'filename','timestamp','timezone','repo_path','git_head', ...
    'git_porcelain','matlab_version','os_platform', ...
    'psat_path','psat_version','psat_entrypoints', ...
    'pgaz_path','pgaz_version','pgaz_provenance', ...
    'commands','test_audit','case_contracts','ybus_comparison', ...
    'mapping_tables','pairwise_metrics','convergence_status', ...
    'gate_statuses','aggregate_gate','raw_output_paths', ...
    'validated_source_commit'};
ok = true; missing = {};
for i = 1:numel(required)
    f = required{i};
    if ~isfield(a,f) || isempty(a.(f))
        ok = false; missing{end+1} = f; %#ok<AGROW>
    end
end
% PSAT entry points must NOT be PGAz function names.
if isfield(a,'psat_entrypoints') && ~isempty(a.psat_entrypoints)
    if contains(a.psat_entrypoints, 'pgaz_pf') || contains(a.psat_entrypoints, 'pgaz_ts')
        ok = false; missing{end+1} = 'psat_entrypoints_mislabeled_as_pgaz'; %#ok<AGROW>
    end
end
end
