function s = classify(field)
%CLASSIFY  Classify an option field for the table's Class/Source column.
%   Returns a short provenance tag. Numerical-method fields are tagged
%   NUMERICAL_METHOD; otherwise CASE_DEFINED (the default since options come
%   from the case catalog or launcher defaults).
switch lower(field)
    case {'max_iter','tolerance','q_limit_tolerance','max_q_limit_switches', ...
            'fd_eps','stability_tolerance','equilibrium_tolerance', ...
            'newton_max_iterations','corrector_abs_tol','corrector_rel_tol', ...
            'max_corrector_iter','corrector_iter','dt','t_end'}
        s = 'NUMERICAL_METHOD';
    case {'model','load_model','method','stepper','corrector_mode', ...
            'pm_mode','integrator'}
        s = 'CASE_DEFINED';
    otherwise
        s = 'CASE_DEFINED';
end
end
