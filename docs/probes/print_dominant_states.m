function print_dominant_states()
load(fullfile('docs','source','figures','kundur_ex126','kundur_ex126_results.mat'),'ssa6');
lam = ssa6.eigenvalues(:);
V = ssa6.mode_shapes;
names = cellstr(string(ssa6.state_names(:)));
[~,idx] = sort(real(lam),'descend');
for ii = 1:numel(idx)
    k = idx(ii);
    if abs(imag(lam(k))) < 1e-3 && real(lam(k)) < -1
        mag = abs(V(:,k));
        [~,ord] = sort(mag,'descend');
        top = ord(1:min(4,numel(ord)));
        fprintf('%2d lam=%9.4f %+9.4fj  ', k, real(lam(k)), imag(lam(k)));
        for j = 1:numel(top)
            fprintf('%s(%.2f) ', names{top(j)}, mag(top(j))/max(mag));
        end
        fprintf('\n');
    end
end
fprintf('--- complex fast modes ---\n');
for ii = 1:numel(idx)
    k = idx(ii);
    if imag(lam(k)) > 1e-3 && real(lam(k)) < -10
        mag = abs(V(:,k));
        [~,ord] = sort(mag,'descend');
        top = ord(1:min(4,numel(ord)));
        fprintf('%2d lam=%9.4f %+9.4fj  ', k, real(lam(k)), imag(lam(k)));
        for j = 1:numel(top)
            fprintf('%s(%.2f) ', names{top(j)}, mag(top(j))/max(mag));
        end
        fprintf('\n');
    end
end
end
