function sat = smib_saturation(psi_at, sat_params)
%SMIB_SATURATION Total and incremental d-axis saturation factors.
%   SAT = SMIB_SATURATION(PSI_AT, SAT_PARAMS) returns the total and
%   incremental saturation factors for a given air-gap flux linkage
%   PSI_AT, using the exponential saturation model of Kundur Section 3.8.
%
%   Inputs:
%     PSI_AT          - air-gap flux linkage magnitude psi_at (pu)
%     SAT_PARAMS      - struct with fields:
%                         Asat, Bsat - saturation curve coefficients
%                         psi_T1     - threshold flux psi_TI (pu)
%
%   Output SAT fields:
%     psi_I       - saturation component of flux (pu)
%     Ksd_total   - total saturation factor  = psi_at/(psi_at+psi_I)
%     Ksd_incr    - incremental saturation factor (Kundur eq 12.118)
%
%   The total factor scales the unsaturated mutual inductance for the
%   initial operating point; the incremental factor is used when relating
%   perturbed quantities (eqs 12.105-12.116).
%
%   Reference: Kundur Sec 3.8 (total) and Sec 12.3.2, eq 12.118 (incremental).

Asat   = sat_params.Asat;
Bsat   = sat_params.Bsat;
psi_T1 = sat_params.psi_T1;

if psi_at <= psi_T1
    % Linear region: no saturation
    psi_I = 0.0;
    Ksd_total = 1.0;
    Ksd_incr = 1.0;
else
    psi_I = Asat * exp(Bsat * (psi_at - psi_T1));
    Ksd_total = psi_at / (psi_at + psi_I);
    Ksd_incr = 1.0 / (1.0 + Bsat * psi_I);
end

sat = struct();
sat.psi_I = psi_I;
sat.Ksd_total = Ksd_total;
sat.Ksd_incr = Ksd_incr;
sat.psi_at = psi_at;
end
