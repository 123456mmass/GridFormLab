function tests=test_no_external_solver_dependency
%TEST_NO_EXTERNAL_SOLVER_DEPENDENCY Guard: no external nonlinear solver in
%   the production scope. The guard recursively scans EVERY .m file under
%   the project root EXCEPT legacy/ (off-path reference code), .git/, and
%   docs/probes/ (off-path probes) -- i.e. everything that pf_init_paths can
%   put on the MATLAB path: root launchers, the +package folders, internal/,
%   compat/, scripts/, docs/.
tests=functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function files = production_m_files(root)
% All .m files under root except legacy/, .git/, docs/probes/.
fl = dir(fullfile(root,'**','*.m'));
files = strings(0,1);
for k=1:numel(fl)
    p = fullfile(fl(k).folder, fl(k).name);
    if contains(p, [filesep 'legacy' filesep]) || contains(p, [filesep 'legacy']) ...
            || contains(p, [filesep '.git' filesep]) || contains(p, [filesep 'probes' filesep])
        continue;
    end
    files(end+1,1) = string(p); %#ok<AGROW>
end
end

function test_production_scope_has_no_external_solver(testCase)
root = fileparts(fileparts(mfilename('fullpath')));
files = production_m_files(root);
forbidden = {'fsolve','optimoptions','fmincon','fminsearch','lsqnonlin','optimset'};
hits = strings(0,2);
for k=1:numel(files)
    src = fileread(files(k));
    for q=1:numel(forbidden)
        pat = ['[^a-zA-Z0-9_]' forbidden{q} '\s*\('];
        if ~isempty(regexp(src, pat, 'once'))
            hits(end+1,:) = {files(k), forbidden{q}}; %#ok<AGROW>
        end
    end
end
testCase.verifyEmpty(hits, ...
    sprintf('Production .m files must not call external solvers. Hits:\n%s', ...
        strjoin(cellstr(hits(:,1)), newline)));
end

function test_legacy_is_off_production_path(testCase)
root = fileparts(fileparts(mfilename('fullpath')));
p = path;
entries = regexp(p, regexptranslate('escape', pathsep), 'split');
legacy_entry = fullfile(root,'legacy');
testCase.verifyFalse(any(strcmp(entries, legacy_entry)), 'legacy/ must not be on the path.');
legacy_fns = {'powerflow_fsolve','synchronous_flux_ssa','kundur_ex126_kundur_ssa', ...
    'kundur_ex126_book_e123_ssa','kundur_ex126_genrou_ssa','kundur_ex126_sixth_order_ssa', ...
    'genpj6_dae','ts_simulate_genpj6','kundur_fault_simulation_6th_order', ...
    'calibrate_kundur_e123_full','calibrate_all_24','kundur_e123_family_compare'};
found = strings(0,1);
for k=1:numel(legacy_fns)
    if ~isempty(which(legacy_fns{k})), found(end+1,1)=string(legacy_fns{k}); end %#ok<AGROW>
end
testCase.verifyEmpty(found, 'Legacy functions must not be reachable on the production path.');
end

function test_production_catalog_has_no_calibrated_kundur(testCase)
root = fileparts(fileparts(mfilename('fullpath')));
files = {fullfile(root,'solve_case.m'), ...
    fullfile(root,'+cases','network_case_catalog.m'), ...
    fullfile(root,'+stability','multicase_sssa.m'), ...
    fullfile(root,'+stability','ts_simulate.m')};
forbidden = {'ts_simulate_genpj6','genpj6_dae','kundur_ex126_kundur_ssa', ...
    'kundur_ex126_book_e123_ssa','kundur_ex126_genrou_ssa','kundur_ex126_sixth_order_ssa', ...
    'synchronous_flux_ssa','kundur_ex126_book_flux_ssa','kundur_fault_simulation_6th_order', ...
    'calibrate_kundur_e123_full','calibrate_all_24'};
hits = strings(0,1);
for f=1:numel(files)
    src = fileread(files{f});
    for q=1:numel(forbidden)
        if ~isempty(regexp(src, ['[^a-zA-Z0-9_]' forbidden{q}],'once'))
            hits(end+1,1)=string(sprintf('%s: %s',files{f},forbidden{q})); %#ok<AGROW>
        end
    end
end
testCase.verifyEmpty(hits, ...
    'Production catalog/launcher must not reference calibrated/legacy Kundur paths.');
end
