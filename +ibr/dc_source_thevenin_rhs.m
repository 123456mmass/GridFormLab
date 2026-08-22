function dv=dc_source_thevenin_rhs(vdc,Pac,p)
%DC_SOURCE_THEVENIN_RHS  dVdc/dt for the non-ideal DC source of the EECON49 IBR.
%
%   dv = ibr.dc_source_thevenin_rhs(vdc,Pac,p)
%
% p comes from ibr.dc_source_thevenin_params, which carries the full derivation.
% Implements
%
%   C dVdc/dt = (Edc - Vdc)/Rdc - Pac/Vdc - max(0,Vdc - Vdc_max)/Rch
%
% Pac is the converter-side AC power vcd*id + vcq*iq on the machine base, i.e.
% the bus power plus the filter loss, which is what the DC bus actually supplies.
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
i_src=(p.Edc-vdc)/p.Rdc;
i_load=Pac/vdc;
i_ch=max(0,vdc-p.Vdc_max)/p.Rch;
dv=(i_src-i_load-i_ch)/p.Cdc;
if ~isfinite(dv)
    error('ibr:dc_source_thevenin:nonfinite','non-finite dVdc/dt.');
end
end
