function line = cpf_opened_plot_line(cpf)
if strcmp(cpf.method, 'CPF Predictor-Corrector')
    line = 'Opened CPF predictor-corrector reference plot.';
else
    line = 'Opened separate CPF plots.';
end
end
