function Y = ts_topology_at(t, opt, Ypre, Yfault, Ypost)
%TS_TOPOLOGY_AT Event-aware network admittance selector.
%   Y = ts_topology_at(T, OPT, YPRE, YFAULT, YPOST) returns the network
%   admittance appropriate for time T according to the fault convention:
%     pre-fault:  T < t_fault        -> Ypre
%     faulted:    t_fault <= T < t_clear -> Yfault  (Ypre + e_f e_f' / Zf)
%     post-fault: T >= t_clear       -> Ypost
%   This is the SINGLE copy used by the fixed-step and adaptive drivers.
%   No fragile floating-point comparison: uses a small absolute floor so an
%   event landing exactly on t_fault/t_clear is classified correctly.

eps_floor = 1e-12;
if opt.fault_enabled
    if t < opt.t_fault - eps_floor
        Y = Ypre;
    elseif t < opt.t_clear - eps_floor
        Y = Yfault;
    else
        Y = Ypost;
    end
else
    Y = Ypre;
end
end

function tf = ts_topology_changed(A, B)
%TS_TOPOLOGY_CHANGED True if two admittance matrices differ.
tf = isequal(size(A),size(B)) && max(abs(A(:)-B(:)),[],'all') == 0;
end
