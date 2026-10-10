function open_cpf_figure(cpf)
%DEPRECATED (Phase C): superseded by the Studio GUI (+studio/launch.m).
%   Header banner only; behavior unchanged.
if strcmp(cpf.method, 'CPF Predictor-Corrector')
    pfapp.open_cpf_reference_figure(cpf);
else
    pf_plot_cpf_results(cpf);
end
end
