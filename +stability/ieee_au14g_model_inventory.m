function inv = ieee_au14g_model_inventory(case_id)
%IEEE_AU14G_MODEL_INVENTORY Inventory of dynamic model blocks required for AU14G.
% This is a planning/coverage helper for model-reconstruction validation. It
% reads RAW/DYR parameters only and reports which component models must be
% implemented before AU14G can be counted as a <0.5% accuracy benchmark.

if nargin < 1, case_id = 1; end
c = cases.ieee_au14g_case(case_id);
inv = struct();
inv.case_name = c.name;
inv.generator_models = count_models({c.dyn.generators.model});
inv.exciter_models = count_models({c.dyn.exciters.model});
inv.pss_models = count_models({c.dyn.pss.model});
inv.generator_count = c.generator_count;
inv.exciter_count = numel(c.dyn.exciters);
inv.pss_count = numel(c.dyn.pss);
inv.required_models = {'GENROE','GENSAL','ESST1A','ESAC1A','IEEEST','SVC'};
inv.implemented_for_reconstruction = {'GENROE_parser','GENSAL_parser','ESST1A_parser','ESAC1A_parser','IEEEST_parser'};
inv.accuracy_benchmark_ready = false;
inv.blocking_reason = ['Full AU14G model-reconstruction is not ready until ', ...
    'GENROE/GENSAL differential equations, ESST1A/ESAC1A exciters, IEEEST PSS, ', ...
    'SVC dynamics, RAW network algebraics, and operating-point initialization ', ...
    'are all assembled without using published A matrices.'];
end

function s = count_models(models)
models = string(models(:));
u = unique(models);
s = struct('model',{},'count',{});
for k = 1:numel(u)
    s(end+1,1) = struct('model',char(u(k)),'count',sum(models==u(k))); %#ok<AGROW>
end
end
