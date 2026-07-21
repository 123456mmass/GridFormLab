function tests = test_ibr_smib_verification_plots()
%TEST_IBR_SMIB_VERIFICATION_PLOTS  Integration test for the dual SMIB script.
%   Verifies that scripts/ibr/smib_verification_plots regenerates one tiled
%   TDS current/power figure per case, emits the PASS tokens, and does not
%   leak figures. Pre-existing artifacts are backed up and restored so the
%   test proves fresh generation without destroying user files permanently.
tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function test_dual_smib_script_generates_tds_plots(tc)
root = pf_init_paths();
script_dir = fullfile(root,'scripts','ibr');
gfl_dir = fullfile(root,'output','figures','smib','gfl_rms10');
gfm_dir = fullfile(root,'output','figures','smib','gfm_no_pll');

names = {'tds_dq_power_signals'};
expected_paths = build_expected_paths({gfl_dir,gfm_dir},names);

% Backup existing artifacts and remove the exact expected paths so the test
% proves regeneration. Restoration happens via onCleanup regardless of failure.
backup = backup_and_remove(expected_paths);
cleanup = onCleanup(@() restore_and_cleanup(backup,expected_paths));

% Temporarily add scripts/ibr to path for the standalone script.
addpath(script_dir);
cleanupPath = onCleanup(@() rmpath(script_dir));

base_figs = numel(findall(groot,'Type','figure'));

text = evalc('smib_verification_plots();');

for k = 1:numel(expected_paths)
    tc.verifyTrue(isfile(expected_paths{k}), ...
        sprintf('Missing expected artifact: %s',expected_paths{k}));
end

tc.verifyEqual(count_token(text,'GFL_SMIB_TDS_CURRENT_POWER_PLOTS = PASS'),1);
tc.verifyEqual(count_token(text,'GFM_NO_PLL_SMIB_TDS_CURRENT_POWER_PLOTS = PASS'),1);
tc.verifyEqual(numel(findall(groot,'Type','figure')),base_figs, ...
    'Script leaked figures.');
end

function paths = build_expected_paths(dirs,names)
paths = {};
for d = 1:numel(dirs)
    for n = 1:numel(names)
        paths{end+1} = fullfile(dirs{d},[names{n} '.fig']); %#ok<AGROW>
        paths{end+1} = fullfile(dirs{d},[names{n} '.png']); %#ok<AGROW>
    end
end
paths = paths(:);
end

function backup = backup_and_remove(expected_paths)
backup = struct('src',{{}},'dst',{{}});
for k = 1:numel(expected_paths)
    if isfile(expected_paths{k})
        dst = [expected_paths{k} '.test_backup']; %#ok<AGROW>
        copyfile(expected_paths{k},dst);
        backup.src{end+1} = expected_paths{k}; %#ok<AGROW>
        backup.dst{end+1} = dst; %#ok<AGROW>
        delete(expected_paths{k});
    elseif isfile([expected_paths{k} '.test_backup'])
        delete([expected_paths{k} '.test_backup']);
    end
end
end

function restore_and_cleanup(backup,expected_paths)
for k = 1:numel(backup.src)
    if isfile(backup.dst{k})
        movefile(backup.dst{k},backup.src{k},'f');
    end
end
for k = 1:numel(expected_paths)
    backup_file = [expected_paths{k} '.test_backup'];
    if isfile(backup_file)
        delete(backup_file);
    end
end
end

function n = count_token(text,token)
n = numel(strfind(text,token));
end
