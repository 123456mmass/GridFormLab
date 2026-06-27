function results = smib_analyze(sys, options)
%SMIB_ANALYZE Eigen-analysis of an SMIB small-signal state matrix.
%   RESULTS = SMIB_ANALYZE(SYS, OPTIONS) computes the eigenvalues, damping
%   ratios, natural/damped frequencies, right and left eigenvectors, mode
%   shapes, and participation factors for the state matrix SYS.A.
%
%   SYS    - struct from SMIB_BUILD_STATE_MATRIX (fields A, state_names, ...)
%   OPTIONS (struct, optional):
%     verbose - print a summary table (default false)
%
%   RESULTS fields:
%     eigenvalues   - column vector of eigenvalues (lambda)
%     damping       - damping ratio zeta for each eigenvalue
%     wn            - undamped natural frequency (rad/s) per eigenvalue
%     freq_Hz       - damped oscillation frequency (Hz) per eigenvalue
%     is_stable     - true if all real parts < 0
%     right_vectors - matrix of right eigenvectors (columns)
%     left_vectors  - matrix of left eigenvectors (rows of inv(V))
%     participation - participation factor matrix (states x modes)
%     state_names   - passed through from SYS
%
%   Reference: Kundur Sec 12.1-12.2 (eigenproperties, participation).

if nargin < 2 || isempty(options)
    options = struct();
end
verbose = get_opt(options, 'verbose', false);

A = sys.A;
n = size(A, 1);

[V, D] = eig(A);
lambda = diag(D);

sigma = real(lambda);
omega = imag(lambda);

% Undamped natural frequency and damping ratio per eigenvalue
wn = sqrt(sigma.^2 + omega.^2);
zeta = zeros(n, 1);
nz = wn > 0;
zeta(nz) = -sigma(nz) ./ wn(nz);

% Damped oscillation frequency in Hz (0 for real eigenvalues)
freq_Hz = abs(omega) / (2 * pi);

% Left eigenvectors: rows of W = inv(V)
W = inv(V);

% Participation factors p_ki = |V(k,i)| * |W(i,k)| (normalized per mode)
participation = abs(V) .* abs(W.');
for i = 1:n
    col_sum = sum(participation(:, i));
    if col_sum > 0
        participation(:, i) = participation(:, i) / col_sum;
    end
end

results = struct();
results.A = A;
results.eigenvalues = lambda;
results.damping = zeta;
results.wn = wn;
results.freq_Hz = freq_Hz;
results.is_stable = all(sigma < 0);
results.right_vectors = V;
results.left_vectors = W;
results.participation = participation;
if isfield(sys, 'state_names')
    results.state_names = sys.state_names;
else
    results.state_names = arrayfun(@(k) sprintf('x%d', k), 1:n, ...
        'UniformOutput', false);
end
results.model = getfield_default(sys, 'model', '');

if verbose
    print_summary(results);
end
end

% ------------------------------------------------------------------------
function value = get_opt(options, name, default)
if isstruct(options) && isfield(options, name) && ~isempty(options.(name))
    value = options.(name);
else
    value = default;
end
end

function value = getfield_default(s, name, default)
if isfield(s, name)
    value = s.(name);
else
    value = default;
end
end

function print_summary(r)
fprintf('\nSMIB small-signal analysis (model %s)\n', r.model);
fprintf('%-22s %-12s %-10s %-10s\n', 'Eigenvalue', 'zeta', 'f (Hz)', 'stable');
for k = 1:numel(r.eigenvalues)
    lam = r.eigenvalues(k);
    fprintf('%8.4f %+8.4fi   %7.4f    %7.4f\n', ...
        real(lam), imag(lam), r.damping(k), r.freq_Hz(k));
end
fprintf('System stable: %d\n', r.is_stable);
end
