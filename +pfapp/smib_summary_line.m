function line = smib_summary_line(res)
%SMIB_SUMMARY_LINE One-line log summary of an SMIB analysis result.

r = res.analyze;
lam = r.eigenvalues;
swing = [];
up = lam(imag(lam) > 1e-3);
if ~isempty(up)
    [~, k] = min(abs(real(up)));
    swing = up(k);
end
if r.is_stable
    status = 'STABLE';
else
    status = 'UNSTABLE';
end
if isempty(swing)
    line = sprintf('SMIB Model %s: %s, %d states, max Re(λ)=%.4f.', ...
        res.model, status, numel(r.state_names), max(real(lam)));
else
    zeta = -real(swing) / abs(swing);
    line = sprintf('SMIB Model %s: %s, %d states, swing λ=%.4f%+.4fj, ζ=%.3f, f=%.3f Hz.', ...
        res.model, status, numel(r.state_names), real(swing), imag(swing), zeta, abs(imag(swing))/(2*pi));
end
end
