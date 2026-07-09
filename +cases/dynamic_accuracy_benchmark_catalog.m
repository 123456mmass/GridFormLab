function catalog = dynamic_accuracy_benchmark_catalog()
%DYNAMIC_ACCURACY_BENCHMARK_CATALOG Model-reconstruction accuracy benchmarks only.
% A benchmark is included here only if our code reconstructs the linearized
% model from published parameters/operating point and compares against
% published eigenvalues.  Published state-space matrices are deliberately
% excluded from this catalog.

catalog = struct('id',{},'name',{},'machines',{},'source',{},'max_error_percent',{},'tolerance_percent',{},'status',{});
% Kundur E12.3 is intentionally excluded until the physical book-flux
% reconstruction passes every published root without calibrated corrections.
add('sauer_pai_e83', 'Sauer-Pai Example 8.3 / corrected Table 8.2', 3, ...
    'Sauer & Pai Power System Dynamics and Stability, Table 8.2', 0.112, 0.5, 'pass');

    function add(id,name,machines,source,maxerr,tol,status)
        catalog(end+1,1) = struct('id',id,'name',name,'machines',machines, ...
            'source',source,'max_error_percent',maxerr,'tolerance_percent',tol,'status',status);
    end
end
