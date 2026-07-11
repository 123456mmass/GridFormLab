function tests = test_artifact_metadata()
%TEST_ARTIFACT_METADATA  Verify the artifact metadata validator requires all
%   provenance fields and rejects PSAT entry points mislabeled as PGAz.

tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function a = full_artifact()
a = struct();
a.filename='output/validation/artifacts/x.md'; a.timestamp='2026-07-11 15:00:00';
a.timezone='+0700'; a.repo_path='/home/birds/Documents/Power-flow';
a.git_head='abc123'; a.git_porcelain='clean'; a.matlab_version='26.1'; a.os_platform='GLNXA64';
a.psat_path='/home/birds/Documents/psat-2.1.11-mat/psat'; a.psat_version='2.1.11';
a.psat_entrypoints='runpsat, fm_spf, psat';   % correct PSAT entry points
a.pgaz_path='/home/birds/Documents/PGAz_V1.1.1'; a.pgaz_version='1.1.1';
a.pgaz_provenance='KMITL 2024, timestamps 2026-03-10';
a.commands='runtests; run_three_way_validation'; a.test_audit='141->139 explained';
a.case_contracts='Ybus match'; a.ybus_comparison='7.3e-15'; a.mapping_tables='gen by bus ID';
a.pairwise_metrics='PSAT/PGAz/Ours'; a.convergence_status='PSAT conv, PGAz completed';
a.gate_statuses='all listed'; a.aggregate_gate='FAIL'; a.raw_output_paths='output/...';
a.validated_source_commit='abc123';
end

function test_full_artifact_passes(testCase)
[ok, missing] = validate_artifact_metadata(full_artifact());
testCase.verifyTrue(ok, 'full artifact must pass');
testCase.verifyTrue(isempty(missing), 'no missing fields');
end

function test_missing_source_commit_fails(testCase)
a = full_artifact(); a = rmfield(a, 'validated_source_commit');
[ok, missing] = validate_artifact_metadata(a);
testCase.verifyFalse(ok, 'missing source commit must fail');
testCase.verifyTrue(ismember('validated_source_commit', missing));
end

function test_psat_entrypoints_mislabeled_as_pgaz_fails(testCase)
a = full_artifact(); a.psat_entrypoints = 'pgaz_pf.m, pgaz_ts.m';  % the bug
[ok, missing] = validate_artifact_metadata(a);
testCase.verifyFalse(ok, 'PSAT entry points mislabeled as PGAz must fail');
testCase.verifyTrue(ismember('psat_entrypoints_mislabeled_as_pgaz', missing));
end

function test_missing_pgaz_provenance_fails(testCase)
a = full_artifact(); a.pgaz_provenance = '';
[ok, missing] = validate_artifact_metadata(a);
testCase.verifyFalse(ok, 'missing PGAz provenance must fail');
testCase.verifyTrue(ismember('pgaz_provenance', missing));
end
