function open_cpf_figure(cpf)
if strcmp(cpf.method, 'CPF Predictor-Corrector')
    pfapp.open_cpf_reference_figure(cpf);
else
    pf_plot_cpf_results(cpf);
end
end
