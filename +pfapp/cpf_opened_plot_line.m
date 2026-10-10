function line = cpf_opened_plot_line(cpf)
%DEPRECATED (Phase C): superseded by the Studio GUI (+studio/launch.m).
%   Header banner only; behavior unchanged.
if strcmp(cpf.method, 'CPF Predictor-Corrector')
    line = 'Opened CPF predictor-corrector reference plot.';
else
    line = 'Opened separate CPF plots.';
end
end
