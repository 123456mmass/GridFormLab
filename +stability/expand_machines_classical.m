function [H,D,Xdp] = expand_machines_classical(mach, ng, gbus, bus_ids, opt)
%EXPAND_MACHINES_CLASSICAL  Map classical machine dynamic data to generator buses.
%   Extracted from ts_simulate's nested expand_machines so classical_dae can
%   reuse the EXACT aggregation logic (coherent classical equivalent:
%   H_agg = sum(H_k); D_agg = sum(D_k); 1/X'd_agg = sum(1/X'd_k)) without
%   duplicating it. Bit-identical to the legacy nested function.
%
%   Always maps by BUS ID (never by index). When multiple machines are connected
%   to the same bus they are aggregated. If a case provides machine data but a
%   generator bus has no matching machine, an ERROR is raised (never a silent
%   default fallback). Defaults H=5, D=0, X'd=0.3 are used ONLY when no machine
%   data is supplied at all.

H = 5.0*ones(ng,1); D = zeros(ng,1); Xdp = 0.30*ones(ng,1);
has_mach = ~isempty(mach) && numel(mach) > 0;

if has_mach
    machBus = [mach.bus];
    for k = 1:ng
        b = gbus(k);
        idx = find(machBus == b);
        if isempty(idx)
            error('expand_machines_classical:noMachineForBus', ...
                ['Generator bus %d has no matching machine data. ' ...
                 'When a case provides .machines, every generator bus ' ...
                 'must have at least one machine entry. ' ...
                 'Add the missing machine or remove the generator bus.'], b);
        end
        Hk  = [mach(idx).H];
        Dk  = [mach(idx).D];
        Xk  = [mach(idx).Xdp];
        H(k)   = sum(Hk);
        D(k)   = sum(Dk);
        Xdp(k) = 1 / sum(1./Xk);
    end
    if any(~isfinite(H)) || any(H <= 0)
        error('expand_machines_classical:badH', 'Aggregated H must be positive and finite (got min=%.4g).', min(H));
    end
    if any(~isfinite(Xdp)) || any(Xdp <= 0)
        error('expand_machines_classical:badXdp', 'Aggregated X''d must be positive and finite (got min=%.4g).', min(Xdp));
    end
end

% Per-run overrides (e.g. classical defaults for MATPOWER cases).
if ~isempty(opt.H),   H=opt.H(:);   if numel(H)==1, H=H*ones(ng,1); end, end
if ~isempty(opt.D),   D=opt.D(:);   if numel(D)==1, D=D*ones(ng,1); end, end
if ~isempty(opt.Xdp), Xdp=opt.Xdp(:); if numel(Xdp)==1, Xdp=Xdp*ones(ng,1); end, end
end
