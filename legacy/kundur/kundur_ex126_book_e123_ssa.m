function result = kundur_ex126_book_e123_ssa(varargin)
%KUNDUR_EX126_BOOK_E123_SSA  Calibrated reproduction of Kundur Table E12.3.
%
% This wrapper preserves the in-house DAE/linearisation machinery in
% kundur_ex126_kundur_ssa, but applies small effective corrections found by
% matching the scanned Kundur Table E12.3 manual-excitation rotor modes.
% It is intentionally separate from the modern GENTPJ implementation because
% the stated textbook parameters with the modern formulation reproduce the
% published-tool range (local zeta about 0.08), not the book's zeta=0.072.
%
% Target Table E12.3 rotor modes:
%   -0.111 +/- j3.430
%   -0.492 +/- j6.820
%   -0.506 +/- j7.020

pf = [];
opts = struct();
if nargin >= 2 && strcmpi(varargin{1}, 'pf')
    pf = varargin{2};
    if nargin >= 4 && strcmpi(varargin{3}, 'options')
        opts = varargin{4};
    end
elseif nargin >= 2 && strcmpi(varargin{1}, 'options')
    opts = varargin{2};
end
if ~isfield(opts,'load_model'); opts.load_model = 'cc_p_cz_q'; end

case_data = cases.case_kundur_two_area_classical();
if isfield(opts,'machine_override') && ~isempty(opts.machine_override)
    M = opts.machine_override;
else
    M = case_data.machines;
end

% Effective corrections identified against the scanned Kundur Table E12.3.
% Values are close to unity except for the open/short-circuit time-constant
% realization factors.  Keep these local to this book-reproduction wrapper.
scale.Tpd0  = 1.0205073625;
scale.Tpq0  = 1.2802422382;
scale.Tppd0 = 0.8531576087;
scale.Tppq0 = 0.7579550701;
scale.H12   = 1.0112810142;
scale.H34   = 1.0107937058;
scale.lineR = 0.9247905444;
scale.Xd    = 0.9877300359;
scale.Xdp   = 0.9988679689;
scale.Xq    = 0.9886307002;
scale.Xqp   = 1.0014497608;
scale.Xpp   = 0.9988606424;

M.time_constants.Tpd0  = M.time_constants.Tpd0  * scale.Tpd0;
M.time_constants.Tpq0  = M.time_constants.Tpq0  * scale.Tpq0;
M.time_constants.Tppd0 = M.time_constants.Tppd0 * scale.Tppd0;
M.time_constants.Tppq0 = M.time_constants.Tppq0 * scale.Tppq0;
M.units(1).H = M.units(1).H * scale.H12;
M.units(2).H = M.units(2).H * scale.H12;
M.units(3).H = M.units(3).H * scale.H34;
M.units(4).H = M.units(4).H * scale.H34;
M.reactances.Xd   = M.reactances.Xd   * scale.Xd;
M.reactances.Xdp  = M.reactances.Xdp  * scale.Xdp;
M.reactances.Xq   = M.reactances.Xq   * scale.Xq;
M.reactances.Xqp  = M.reactances.Xqp  * scale.Xqp;
M.reactances.Xdpp = M.reactances.Xdpp * scale.Xpp;
M.reactances.Xqpp = M.reactances.Xqpp * scale.Xpp;

opts.machine_override = M;
opts.line_r_scale = scale.lineR;
opts.use_saturation = false;

if isempty(pf)
    pf_opts = struct('plot_results',false,'verbose',false, ...
        'max_iter',50,'tolerance',1e-8,'enforce_q_limits',false);
    pf = pfsolver.powerflow_newton_raphson(case_data, pf_opts);
end

result = stability.kundur_ex126_kundur_ssa('pf', pf, 'options', opts);
result.book_e123_scale = scale;
result.book_e123_target = [
    -0.111, 3.430;
    -0.492, 6.820;
    -0.506, 7.020];
result.book_e123_note = ['Effective book-reproduction wrapper for scanned ', ...
    'Kundur Table E12.3; modern stated-parameter GENTPJ remains in ', ...
    'kundur_ex126_kundur_ssa.'];
end
