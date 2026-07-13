function sm = report_style_map()
%REPORT_STYLE_MAP  Single documented style map for all report figures.
%   SM = report_style_map() returns a struct of color/marker/line-style
%   specifications for every series that appears in the report. All figures
%   use THIS map so Ours/PSAT/PGAz/book/adaptive/fixed are visually
%   consistent across every plot.
%
%   Series keys: ours, psat, pgaz, book, adaptive, fixed, avr, manual.
%   Each value is a struct with fields: color (RGB row), marker (char),
%   line_style (char), line_width (scalar), display (string for legend).
%
%   Design rules (mission graph requirements):
%     - Ours is the primary series (solid, blue, filled markers).
%     - PSAT/PGAz are reference series (distinct colors, open markers).
%     - Book is a sourced reference (black, circle, thick edge).
%     - Adaptive vs fixed differ by line style (solid vs dashed).
%     - No smoothing; no clipping; fault/clear lines marked separately.

sm = struct();

% --- Tool series (PF + TS comparisons) ---
sm.ours = struct('color',[0.00 0.45 0.74], 'marker','o', 'line_style','-', ...
    'line_width',1.8, 'display','Ours (in-house)');
sm.psat = struct('color',[0.85 0.33 0.10], 'marker','s', 'line_style','--', ...
    'line_width',1.5, 'display','PSAT (reference)');
sm.pgaz = struct('color',[0.47 0.67 0.19], 'marker','^', 'line_style',':', ...
    'line_width',1.5, 'display','PGAz (reference)');
sm.book = struct('color',[0.10 0.10 0.10], 'marker','o', 'line_style','none', ...
    'line_width',1.4, 'display','Book (sourced)');

% --- Stepper series (fixed vs adaptive) ---
sm.fixed = struct('color',[0.00 0.45 0.74], 'marker','none', 'line_style','-', ...
    'line_width',1.6, 'display','Fixed-step');
sm.adaptive = struct('color',[0.85 0.33 0.10], 'marker','none', 'line_style','--', ...
    'line_width',1.6, 'display','Adaptive-step');

% --- Excitation series (Padiyar AVR vs manual) ---
sm.avr = struct('color',[0.00 0.45 0.74], 'marker','none', 'line_style','-', ...
    'line_width',1.6, 'display','AVR');
sm.manual = struct('color',[0.85 0.33 0.10], 'marker','none', 'line_style','--', ...
    'line_width',1.4, 'display','Manual excitation');

% --- Event lines (fault on / fault cleared) ---
sm.fault_on = struct('color',[0.75 0.10 0.10], 'line_style','--', ...
    'line_width',1.1, 'display','Fault on');
sm.fault_clear = struct('color',[0.75 0.10 0.10], 'line_style','--', ...
    'line_width',1.1, 'display','Fault cleared');

% --- Reference axis (imaginary axis at Re=0 for SSSA plots) ---
sm.imag_axis = struct('color',[0 0 0], 'line_style','--', 'line_width',1.0, ...
    'display','Re(\lambda)=0');

% --- Generator palette (for multi-generator traces) ---
sm.generators = [0.00 0.45 0.74; 0.85 0.33 0.10; 0.47 0.67 0.19; ...
                 0.49 0.18 0.56; 0.30 0.30 0.30; 0.93 0.69 0.13; ...
                 0.00 0.00 0.00; 0.38 0.38 0.38];

% --- Figure defaults ---
sm.dpi = 250;            % export resolution (>=200 dpi per mission)
sm.fig_color = 'w';      % white background
sm.font_size = 10;
sm.font_name = 'Helvetica';
end
