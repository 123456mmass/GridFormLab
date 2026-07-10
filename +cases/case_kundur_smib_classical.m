function case_data = case_kundur_smib_classical()
%CASE_KUNDUR_SMIB_CLASSICAL Kundur Example 12.2 - SMIB classical model.
%   Single-machine infinite-bus system with the generator represented by
%   the classical model (constant voltage E' behind transient reactance
%   X'd). State variables: [delta_omega_r; delta_delta].
%
%   Reference: P. Kundur, "Power System Stability and Control",
%   Chapter 12, Section 12.3.1, Example 12.2, printed pages 732-737.

case_data = struct();
case_data.system_name = 'Kundur SMIB - Classical Model (Example 12.2)';
case_data.model = 'A';
case_data.reference = struct( ...
    'source', 'Kundur, Power System Stability and Control, Sec 12.3.1, Example 12.2', ...
    'pdf_file', 'prabha_kundur_power_system_stability_an.pdf', ...
    'printed_pages', '732-737');

case_data.base_values = struct( ...
    'S_base_MVA', 2220, ...
    'V_base_kV', 24, ...
    'frequency_Hz', 60);

% Machine dynamic parameters (per unit on machine base)
case_data.machine = struct( ...
    'H', 3.5, ...        % inertia constant (MW.s/MVA)
    'KD', 0.0, ...       % damping torque coefficient (swept in study)
    'Xd_t', 0.3);        % transient reactance X'd (pu)

% Network: total external reactance between E' node and infinite bus.
% Kundur Ex 12.2: X_E = jX_HT + jX_LT split lines = 0.5 || ? -> equivalent.
% Per the example, XTR (transformer) + line gives X_E = 0.65 pu, so that
% XT = X'd + X_E = 0.3 + 0.65 = 0.95 pu.
case_data.network = struct( ...
    'X_E', 0.65);        % external reactance E' -> infinite bus (pu)

% Operating point (terminal conditions), Kundur Ex 12.2
case_data.operating = struct( ...
    'P', 0.9, ...        % active power output (pu)
    'Q', 0.3, ...        % reactive power output (pu, overexcited)
    'Et_mag', 1.0, ...   % generator terminal voltage magnitude (pu)
    'Et_ang_deg', 36.0, ...   % terminal voltage angle (deg)
    'EB_mag', 0.995, ... % infinite bus voltage magnitude (pu)
    'EB_ang_deg', 0.0);  % infinite bus angle reference (deg)

% Golden reference solution (Kundur Example 12.2, pages 732-735)
case_data.reference_solution = struct( ...
    'delta0_deg', 49.92, ...
    'Ep_mag', 1.123, ...      % |E'| (pu)
    'Ep_ang_deg', 13.92, ...  % angle of E' wrt terminal (deg)
    'XT', 0.95, ...
    'Ks', 0.757, ...          % synchronizing torque coefficient
    'wn_rad', 6.387, ...      % undamped natural frequency (rad/s)
    'fn_Hz', 1.0165, ...      % natural frequency (Hz)
    'eig_KD0', [0 + 6.39i; 0 - 6.39i], ...
    'eig_KD10', [-0.714 + 6.35i; -0.714 - 6.35i], ...
    'zeta_KD10', 0.112, ...
    'eig_KDneg10', [0.714 + 6.36i; 0.714 - 6.36i]);
case_data=cases.standardize_study_case(case_data,'smib');
end
