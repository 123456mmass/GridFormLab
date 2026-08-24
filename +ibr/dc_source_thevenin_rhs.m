function dv=dc_source_thevenin_rhs(vdc,idc,Pac,p)
%DC_SOURCE_THEVENIN_RHS  [dVdc/dt; dIdc/dt] for the non-ideal DC source.
%
%   dv = ibr.dc_source_thevenin_rhs(vdc,idc,Pac,p)
%
% p comes from ibr.dc_source_thevenin_params, which carries the full derivation.
% Implements the two plant rows of the DC circuit,
%
%   C     dVdc/dt = Idc - Pac/Vdc - max(0,Vdc - Vdc_max)/Rch
%   tau_s dIdc/dt = (Edc - Vdc)/Rdc - Idc
%
% Pac is the converter-side AC power vcd*id + vcq*iq on the machine base, i.e.
% the bus power plus the filter loss, which is what the DC bus actually supplies.
%
% Idc is a STATE, not the static Thevenin current. An earlier revision evaluated
% (Edc-Vdc)/Rdc directly in the Vdc row, which is the tau_s -> 0 limit of these
% two equations; that limit is recovered exactly and is recorded in the params
% helper as the degeneracy target.
%
% The chopper term is continuous and Lipschitz; it is non-differentiable only on
% the surface Vdc = Vdc_max, in the same way as the current limiter. No
% activation counter is kept here: this function is evaluated many times per
% accepted step inside the Newton iteration, so a counter would measure solver
% effort rather than physics. Whether the chopper conducted on a trajectory is
% decided afterwards from max(Vdc) against Vdc_max, which is an exact test
% because the conduction condition depends on Vdc alone.

if ~isfinite(vdc) || vdc<=1e-6
    error('ibr:dc_source_thevenin:dcVoltage', ...
        'V_dc must remain finite and positive; got %g.',vdc);
end
if ~isfinite(idc)
    error('ibr:dc_source_thevenin:dcCurrent', ...
        'I_dc must remain finite; got %g.',idc);
end
i_load=Pac/vdc;
i_ch=max(0,vdc-p.Vdc_max)/p.Rch;
dvdc=(idc-i_load-i_ch)/p.Cdc;
didc=((p.Edc-vdc)/p.Rdc-idc)/p.tau_s;
dv=[dvdc;didc];
if any(~isfinite(dv))
    error('ibr:dc_source_thevenin:nonfinite','non-finite DC-circuit RHS.');
end
end
