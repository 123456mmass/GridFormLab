function [lambda_step, lambda_max, min_voltage, max_steps] = predictor_defaults(num_buses)
%PREDICTOR_DEFAULTS CPF predictor-corrector parameters by system size.

if num_buses <= 5
    lambda_step = 0.05; lambda_max = 3.0; min_voltage = 0.50; max_steps = 100;
elseif num_buses <= 14
    lambda_step = 0.04; lambda_max = 3.0; min_voltage = 0.45; max_steps = 100;
elseif num_buses <= 30
    lambda_step = 0.03; lambda_max = 3.0; min_voltage = 0.30; max_steps = 140;
else
    lambda_step = 0.02; lambda_max = 2.5; min_voltage = 0.30; max_steps = 180;
end
end
