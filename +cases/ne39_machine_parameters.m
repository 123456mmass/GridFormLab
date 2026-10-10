function p = ne39_machine_parameters()
%NE39_MACHINE_PARAMETERS  Project-derived machine dynamics for the 39-bus case.
%
%   p = cases.ne39_machine_parameters() returns the machine dynamic data for
%   the 10 machines of the New England 39-bus system, TOGETHER WITH a
%   declaration of where each number came from and what base it is on.
%
%   classification is 'PROJECT_DERIVED'.  These are NOT published New England
%   parameters: no H, D or X'd table for these 10 machines exists in this
%   repository, in this machine's MATLAB/Python installations, or in the ~44
%   PDFs under docs/ (the canonical candidates -- Athay, Podmore & Virmani,
%   IEEE Trans. PAS-98(2):573-584, 1979, and Pai, "Energy Function Analysis for
%   Power System Stability", Kluwer, 1989 -- are not present locally).  What
%   IS present is the published IEEE RTS-1996 dynamic table, and the owner's
%   decision is that the 39-bus machines are derived from it PER MACHINE CLASS
%   by the stated rule below.  A value produced by a stated, checkable rule is
%   legitimate project data; the rule is the claim, and it is auditable.
%
%   =====================================================================
%   DERIVATION 1 -- THE CLASS MAPPING (PROJECT_DERIVED, stated rule)
%   =====================================================================
%   The source's own machine type labels (raw.generator_sites, i.e.
%   +cases/ne39_raw.m:223-225, reproduced verbatim from the published case)
%   are mapped onto the RTS-1996 Table 15 unit groups:
%
%       source label        -> RTS class   why this class
%       -------------------    ---------   ----------------------------------
%       hydro              -> U50         the only hydro group in Table 15
%       nuke01..nuke05     -> U400        largest steam group; nuclear base
%                                         units sit at the top of the RTS
%                                         size range (400 MW)
%       fossil01/02/04     -> U350        mid-size steam group, 350 MW
%       interconnection    -> U400        PROJECT CHOICE, see below
%
%   BUS 39 ("interconnection") IS NOT A REAL MACHINE.  It is the published
%   case's equivalent of the external US/Canada system that New England
%   imports from; it has no physical unit type, and no Table 15 row can be
%   "correct" for it.  The project adopts U400 for it, on the stated ground
%   that the external-system equivalent must not be given a SMALLER unit class
%   than any real machine in the case (bus 39 carries the case's largest Pg,
%   1000 MW, and stands in for an aggregation of many units), and U400 is the
%   largest group Table 15 publishes.  This is a modelling choice by the
%   project, not a sourced value, and it is exactly the kind of choice the
%   sensitivity test in tests/test_ne39_dynamics_sensitivity.m exists to
%   bound.  Alternative adoptions (U350, or a flat H) are NOT covered by that
%   test -- it scales inertia, it does not re-map classes.
%
%   =====================================================================
%   DERIVATION 2 -- THE CONVERSION (the source's own base rules)
%   =====================================================================
%   Table 15 Notes 3-4, as recorded in-repo at
%   +cases/case_ieee_rts24_pgaz.m:311-323, with the machine's OWN Pg in place
%   of the RTS unit's rating:
%
%       H_sys   = H_RTS   * (Pg_NE39_MW / 100)      [Note 4: H in MJ/MW]
%       Xdp_sys = Xdp_RTS * (100 / Smva_RTS)        [Note 3: X'd on unit MVA]
%       D_sys   = D_RTS                             [= 0.0 for every group]
%
%   H is declared on the MW rating and X'd on the MVA rating -- exactly the
%   bases Table 15 quotes them on -- and cases.case_ne39 performs the
%   arithmetic by dispatching on those two declarations.  Damping is carried
%   AS PUBLISHED: Table 15 lists D = 0.0 for every unit group, and the project
%   does not invent damping to make the case look better damped.  A zero-D
%   classical model has undamped electromechanical modes; that is a property
%   of the published data, and the sensitivity test reports it rather than
%   hiding it.
%
%   Worked example -- bus 31 (nuke01 -> U400, Pg = 677.871 MW):
%       H_sys   = 5.0  * (677.871/100)  = 33.89355 s
%       Xdp_sys = 0.40 * (100/471)      = 0.08492569 pu
%       D_sys   = 0.0
%   Every other row is the same two multiplications with that machine's own
%   Pg and its class's Table 15 row.  Nothing is fitted.
%
%   =====================================================================
%   WHAT THIS DOES AND DOES NOT LICENSE
%   =====================================================================
%   Any stability claim made on this case in a report or deck is a claim about
%   a PROJECT_DERIVED model.  It may be stated ONLY together with the
%   sensitivity test on the derived inertia
%   (tests/test_ne39_dynamics_sensitivity.m), which re-runs the classical SSSA
%   with H scaled on every machine and reports how far the answer moves.  The
%   class mapping is NOT covered by that test and must be stated as an
%   assumption wherever a result depends on it.
%
%   The conversion arithmetic, the RTS-24 machines shape and the resulting
%   dynamic state are pinned by tests/test_ne39_case.m.
%
%   See also cases.case_ne39, cases.ne39_raw, cases.case_ieee_rts24_pgaz,
%   tests.test_ne39_dynamics_sensitivity.

p = struct();

% ---- WHERE THE NUMBERS CAME FROM, AND WHAT THEY ARE -----------------------
p.source = [ ...
    'PROJECT_DERIVED from IEEE RTS-1996 Table 15 dynamic data ' ...
    '(https://labs.ece.uw.edu/pstca/rts/rts96/Table-15.txt), carried in-repo ' ...
    'at +cases/case_ieee_rts24_pgaz.m:205-220, mapped onto the New England ' ...
    '39-bus machines per unit class (see this file''s header) with the ' ...
    'machine''s own Pg. Not published New England parameters.'];
p.classification = 'PROJECT_DERIVED';
p.units_note = [ ...
    'PROJECT_DERIVED, not published New England machine data. Class mapping: ' ...
    'hydro->RTS U50, nuke*->RTS U400, fossil*->RTS U350, and bus 39 ' ...
    '(interconnection, the external-system equivalent, not a real machine) ' ...
    '->RTS U400 by project choice. Per machine: H_sys = H_RTS*(Pg_MW/100), ' ...
    'Xdp_sys = Xdp_RTS*(100/Smva_RTS), D_sys = D_RTS = 0.0 as published. ' ...
    'Stability claims on this case require the H-sensitivity test in ' ...
    'tests/test_ne39_dynamics_sensitivity.m.'];

% ---- THE BASES THE TABLE QUOTES THE NUMBERS ON ---------------------------
% Table 15 Notes 3-4 (transcribed at +cases/case_ieee_rts24_pgaz.m:180-188,
% 311-323): H is MJ/MW, i.e. referenced to the machine's MW rating; X'd is on
% the unit's own MVA base; D is dimensionless on the same base as H.
%
% This declaration is NOT decoration -- cases.case_ne39 dispatches its unit
% conversion on it, because the two conversion directions in this repository
% point opposite ways:
%   +cases/case_ieee14bus_eecon49_switch.m:123 stores H on the MACHINE base
%       (machine_to_system = 100/615; H = 2.5*machine_to_system), because the
%       EMF6 route divides by the ratio internally.
%   +cases/case_ieee_rts24_pgaz.m:262 stores H on the SYSTEM base
%       (H = H_table*(P_unit_MW/100); Xdp = Xdp_table*(100/S_unit_MVA)).
% This file is the second kind, because it carries the same Table 15 rows.
%
% Allowed values:
%   H_base, D_base : 'MW_rating' | 'MVA_rating' | 'system_100'
%   Xdp_base       : 'MVA_rating' | 'system_100'
p.H_base = 'MW_rating';
% D_table is 0.0 for every Table 15 group, so D_sys is 0.0 under any legal
% declaration; 'MW_rating' is declared to match the H column's base rather
% than to imply a conversion that changes a number.
p.D_base = 'MW_rating';
p.Xdp_base = 'MVA_rating';

% ---- THE RTS-1996 TABLE 15 ROWS USED (verbatim, in-repo) ------------------
% Copied field-for-field from +cases/case_ieee_rts24_pgaz.m:210,213,215.
% Pmw = MW rating (feeds H), Smva = MVA base (feeds X'd), per Notes 3 and 4.
rts = struct( ...
    'U50',  struct('Pmw', 50,  'Smva', 53,  'Xdp', 0.28, 'H', 3.5, 'D', 0.0), ...
    'U350', struct('Pmw', 350, 'Smva', 412, 'Xdp', 0.30, 'H', 3.0, 'D', 0.0), ...
    'U400', struct('Pmw', 400, 'Smva', 471, 'Xdp', 0.40, 'H', 5.0, 'D', 0.0));

% ---- THE UNIT TABLE ------------------------------------------------------
% One entry per machine, in the source's own order (buses 30..39).  Fields:
%   gen_id     char    label used in reports, e.g. 'G30'
%   bus        double  external bus number, one of 30:39
%   P_MW       double  machine MW rating -> the machine's own Pg (MW) from the
%                      published case, which is what H is scaled by
%   S_MVA      double  RTS class Smva -- the base X'd is converted from
%   H          double  RTS class H, on p.H_base (MW rating)
%   D          double  RTS class D, on p.D_base (0.0 as published)
%   Xdp        double  RTS class X'd, on p.Xdp_base (unit MVA)
%   rts_class  char    the Table 15 row this machine's values come from
%   source_type char   the source's OWN type label for this machine
%
% The source's own machine identities, cross-checked against
% +cases/ne39_raw.m:223-225 and the Pg column of raw.gen (rows 30..39):
%   30 hydro | 31 nuke01 | 32 nuke02 | 33 fossil02 | 34 fossil01
%   35 nuke03 | 36 fossil04 | 37 nuke04 | 38 nuke05 | 39 interconnection
rows = { ...
    'G30', 30, 250.000, 'hydro',           'U50'; ...
    'G31', 31, 677.871, 'nuke01',          'U400'; ...
    'G32', 32, 650.000, 'nuke02',          'U400'; ...
    'G33', 33, 632.000, 'fossil02',        'U350'; ...
    'G34', 34, 508.000, 'fossil01',        'U350'; ...
    'G35', 35, 650.000, 'nuke03',          'U400'; ...
    'G36', 36, 560.000, 'fossil04',        'U350'; ...
    'G37', 37, 540.000, 'nuke04',          'U400'; ...
    'G38', 38, 830.000, 'nuke05',          'U400'; ...
    'G39', 39, 1000.000, 'interconnection', 'U400'};

n = size(rows, 1);
p.unit = struct('gen_id', {}, 'bus', {}, 'P_MW', {}, 'S_MVA', {}, ...
    'H', {}, 'D', {}, 'Xdp', {}, 'rts_class', {}, 'source_type', {});
for k = 1:n
    cls = rows{k, 5};
    t = rts.(cls);
    p.unit(k) = struct( ...
        'gen_id', rows{k, 1}, ...
        'bus', rows{k, 2}, ...
        'P_MW', rows{k, 3}, ...
        'S_MVA', t.Smva, ...
        'H', t.H, ...
        'D', t.D, ...
        'Xdp', t.Xdp, ...
        'rts_class', cls, ...
        'source_type', rows{k, 4});
end

end
