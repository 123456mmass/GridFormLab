function bundle = synthetic_sssa_bundle(case_data, opt)
%SYNTHETIC_SSSA_BUNDLE  Test-only SSSA bundle fixture (B2).
%   Returns a model BUNDLE with bundle.sssa.model = a minimal linear 2-state,
%   4-algebraic SSSA model with an ANALYTIC eigenvalue oracle. TEST-ONLY
%   (tests/+fixtures, called as fixtures.synthetic_sssa_bundle). No +ibr.
%
%   The model: x = [delta; omega], y = [Re(V1); Im(V1); Re(V2); Im(V2)].
%   f(x,y) = A*x (linear swing, A = [0 1; -1 0]). The analytic eigenvalues
%   of A are +/- i (undamped swing). g(x,y) = KCL (synthetic linear).
%
%   Source: project B2 design. SSSA analytic oracle: eig(A) = [+1i; -1i].

if nargin < 1 || isempty(case_data)
    case_data = struct('name','synthetic_sssa'); %#ok<NASGU>
end
if nargin < 2 || isempty(opt), opt = struct(); end %#ok<NASGU>
x0 = [0; 1.0]; y0 = [1.0; 0; 1.0; 0];
A = [0, 1; -1, 0];   % analytic eigenvalues +/- i
f = @(x,y) A*x;
g = @(x,y) [y(1)-1.0; y(2)-0; y(3)-1.0; y(4)-0];
sssa_model = struct('x0',x0,'y0',y0,'f',f,'g',g, ...
    'state_names',{{'delta','omega'}}, ...
    'metadata',struct('engine','stability.multimachine_ssa','plugin','synthetic_linear'));
bundle = struct();
bundle.sssa = struct('model',sssa_model);
bundle.metadata = struct('dispatch','explicit_model_fn');
end
