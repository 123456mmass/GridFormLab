function [lambda_step, lambda_max, min_voltage, max_steps] = load_scaling_defaults(num_buses)
%LOAD_SCALING_DEFAULTS CPF load-scaling parameters by system size.

if num_buses <= 5
    lambda_step = 0.05; lambda_max = 1.5; min_voltage = 0.65; max_steps = 60;
elseif num_buses <= 14
    lambda_step = 0.05; lambda_max = 1.5; min_voltage = 0.65; max_steps = 70;
elseif num_buses <= 30
    lambda_step = 0.04; lambda_max = 1.5; min_voltage = 0.60; max_steps = 90;
else
    lambda_step = 0.03; lambda_max = 1.2; min_voltage = 0.60; max_steps = 120;
end
end
