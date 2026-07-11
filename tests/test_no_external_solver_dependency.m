function tests=test_no_external_solver_dependency
tests=functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

function test_production_has_no_optimization_toolbox_solver(testCase)
root=fileparts(fileparts(mfilename('fullpath')));
dirs={'+pfsolver','+stability','+smib','+pfapp','+pfchecks','+cases','internal'};
forbidden={['f','solve\s*\('],['optim','options\s*\('], ...
    ['fmin','con\s*\('],['fmin','search\s*\(']};
hits=strings(0,1);
for d=1:numel(dirs)
    files=dir(fullfile(root,dirs{d},'**','*.m'));
    for k=1:numel(files)
        path=fullfile(files(k).folder,files(k).name);
        source=fileread(path);
        for p=1:numel(forbidden)
            if ~isempty(regexpi(source,forbidden{p},'once'))
                hits(end+1,1)=string(path); %#ok<AGROW>
            end
        end
    end
end
verifyEmpty(testCase,unique(hits), ...
    'Production code must not depend on Optimization Toolbox solvers.');
end

function test_legacy_calibrated_code_is_off_production_path(testCase)
% The relocated fsolve-based and calibrated-Kundur files must not be reachable
% from the production MATLAB path (legacy/ is intentionally not on it).
root=fileparts(fileparts(mfilename('fullpath')));
pf_init_paths();
legacy_fns={'synchronous_flux_ssa','kundur_ex126_book_flux_ssa','sauer_pai_flux_ssa', ...
    'genpj6_dae','ts_simulate_genpj6','kundur_fault_simulation_6th_order', ...
    'kundur_e123_family_compare','kundur_e123_primitive_compare', ...
    'sauer_pai_ex83_ssa_tmp','sauer_pai_ex83_ssa_load_tmp','sauer_pai_ex83_ssa_torque_tmp'};
found=strings(0,1);
for k=1:numel(legacy_fns)
    if ~isempty(which(legacy_fns{k}))
        found(end+1,1)=string(legacy_fns{k}); %#ok<AGROW>
    end
end
verifyEmpty(testCase,found, ...
    'Legacy/calibrated functions must not be on the production path.');
% legacy/ folder itself must not appear as a path entry (belt-and-suspenders;
% the which() checks above already prove the functions are unreachable).
ents = regexp(path, regexptranslate('escape', pathsep), 'split');
verifyFalse(testCase, any(strcmp(ents, fullfile(root,'legacy'))), ...
    'legacy/ must not be on the MATLAB path.');
end

function test_compat_fsolve_confined_to_reference_tool(testCase)
% fsolve is allowed ONLY in compat/powerflow_fsolve.m (a reference comparison
% tool), nowhere else under compat/ or scripts/.
root=fileparts(fileparts(mfilename('fullpath')));
scan_dirs={'compat'};
hits=strings(0,1);
for d=1:numel(scan_dirs)
    files=dir(fullfile(root,scan_dirs{d},'**','*.m'));
    for k=1:numel(files)
        p=fullfile(files(k).folder,files(k).name);
        src=fileread(p);
        if ~isempty(regexpi(src,'fsolve\s*\(','once'))
            hits(end+1,1)=string(p); %#ok<AGROW>
        end
    end
end
verifyEqual(testCase,numel(hits),1,'compat/ must contain exactly one fsolve file.');
verifyEqual(testCase,hits(1),string(fullfile(root,'compat','powerflow_fsolve.m')));
end

function test_production_catalog_has_no_calibrated_kundur(testCase)
% The production launcher/catalog must not dispatch to the calibrated
% GENTPJ path or any moved legacy model.
root=fileparts(fileparts(mfilename('fullpath')));
files={fullfile(root,'solve_case.m'), ...
    fullfile(root,'+cases','network_case_catalog.m'), ...
    fullfile(root,'+stability','multicase_sssa.m'), ...
    fullfile(root,'+stability','ts_simulate.m')};
forbidden={'ts_simulate_genpj6','genpj6_dae','kundur_ex126_kundur_ssa', ...
    'synchronous_flux_ssa','kundur_ex126_book_flux_ssa','kundur_fault_simulation_6th_order'};
hits=strings(0,1);
for f=1:numel(files)
    src=fileread(files{f});
    for p=1:numel(forbidden)
        if ~isempty(regexp(src,['[^a-zA-Z0-9_]' forbidden{p}],'once'))
            hits(end+1,1)=string(sprintf('%s: %s',files{f},forbidden{p})); %#ok<AGROW>
        end
    end
end
verifyEmpty(testCase,hits, ...
    'Production catalog/launcher must not reference calibrated/legacy Kundur paths.');
end
