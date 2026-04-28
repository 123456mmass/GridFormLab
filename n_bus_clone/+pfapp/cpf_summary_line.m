function line = cpf_summary_line(cpf)
if cpf.nose_detected && cpf.nose_index > 0
    line = sprintf('%s: points=%d, nose lambda=%.4f, nose V=%.4f pu, last lambda=%.4f, stop=%s', ...
        cpf.method, numel(cpf.lambdas), cpf.nose_lambda, cpf.nose_voltage, cpf.lambdas(end), cpf.stop_reason);
else
    line = sprintf('%s: points=%d, last lambda=%.4f, target V=%.4f pu, stop=%s', ...
        cpf.method, numel(cpf.lambdas), cpf.lambdas(end), cpf.target_voltage(end), cpf.stop_reason);
end
end
