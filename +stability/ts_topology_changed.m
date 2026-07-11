function tf = ts_topology_changed(A, B)
%TS_TOPOLOGY_CHANGED True if two admittance matrices DIFFER.
%   TF = ts_topology_changed(A, B) returns true when A and B have different
%   dimensions or any element differs. Returns false only when they are
%   identical (same size, all elements equal).
tf = ~isequal(size(A),size(B)) || max(abs(A(:)-B(:)),[],'all') > 0;
end
