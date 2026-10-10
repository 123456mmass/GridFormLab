function c = layout_constants()
%LAYOUT_CONSTANTS  Single-file visual tokens for the Studio GUI.
%   c = studio.ui.layout_constants() returns every colour, font and band
%   metric the studio layout uses, so the app retunes from one file.
%
%   Token set (frozen from the visual spec):
%     navy            [0 0 0.5]        band headers, active accents
%     bg              [1 1 1]          window and panel background
%     button_idle     [0.98 0.98 0.98] idle push-button background
%     text_grey       [0.4 0.4 0.4]    read-only text colour
%     hover_bg        [0 0 0.95]       hovered button background
%     hover_fg        [1 1 1]          hovered button foreground
%     font_name       'Arial'          UI font
%     font_size       9                UI font size
%     mono_font_name  'Courier New'    eigenvalue box font
%     mono_font_size  8                eigenvalue box font size
%     copyright_size  8                bottom copyright strip font size
%
%   See also: studio.ui.BUILD_LAYOUT, studio.LAUNCH.

c = struct();

% --- colour tokens ---
c.navy = [0 0 0.5];
c.bg = [1 1 1];
c.button_idle = [0.98 0.98 0.98];
c.text_grey = [0.4 0.4 0.4];
c.hover_bg = [0 0 0.95];
c.hover_fg = [1 1 1];
c.white = [1 1 1];
c.black = [0 0 0];

% --- font tokens ---
c.font_name = 'Arial';
c.font_size = 9;
c.mono_font_name = 'Courier New';
c.mono_font_size = 8;
c.copyright_font_size = 8;

% --- band metrics (pixels, figure [80 80 1180 760]) ---
c.figure_position = [80 80 1180 760];
c.fig_w = c.figure_position(3);
c.fig_h = c.figure_position(4);
c.toolbar_h = 95;                 % three strips: navy / white "Data:" / navy
c.strip_h = 31;
c.band_gap = 8;
c.header_h = 26;                  % navy 'Overview' / 'Output' header strips
c.button_size = [75 25];          % analysis button grid cell
c.button_pitch = [85 33];         % 3x3 grid pitch (PGAz-faithful)
c.grid_n = 3;                     % 3x3 button grid
c.segment_count = 40;             % progress bar segment patches

% --- copy ---
c.copyright_text = ['(c) 2026 N-Bus Power Flow Studio - base MATLAB, in-house ' ...
    'solvers only. Visual language after PGAz v1.3.'];
end
