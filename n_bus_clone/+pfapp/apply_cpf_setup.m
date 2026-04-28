function apply_cpf_setup(app, setup)
%APPLY_CPF_SETUP Push auto-calibrated CPF values back into UI fields.

app.target_bus_field.Value = setup.target_bus;
app.lambda_step_field.Value = setup.lambda_step;
app.lambda_max_field.Value = setup.lambda_max;
app.min_voltage_field.Value = setup.min_voltage;
app.max_iter_field.Value = setup.max_steps;
end
