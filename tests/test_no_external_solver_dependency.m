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
