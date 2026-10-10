function c = network_case_catalog(gui_visible)
%NETWORK_CASE_CATALOG Authoritative list of runnable network case loaders.
%   Every entry is a zero-argument loader returning power_case/1.0 and is
%   exposed by solve_case for PF, SSSA and TS.  Raw-data helpers, catalogs,
%   converters and study_case/1.0 loaders are intentionally not entries.
%
%   GUI_VISIBLE is a DISPLAY FILTER, not a registry trim.  The owner keeps the
%   working set to the two production networks (2026-09-26: the starter cases
%   are no longer used; the main cases are IEEE 14 and the 39-bus), so only
%   those two are offered in the case-selection list.  Everything else stays
%   in this catalog on purpose: solve_case resolves by id, scripts/reporting/
%   runs the Padiyar and RTS reports from it, and the TS routing tests use
%   several entries as fixtures.  Removing them would break 12 files to hide
%   a dropdown row.  A hidden entry is therefore still fully runnable.
%
%   c = NETWORK_CASE_CATALOG(GUI_VISIBLE) overrides the offer list.  This
%   exists so the fail-closed check below is reachable from a test; production
%   callers omit the argument and get the two production networks.
%
%   See also wizard.discover_cases, wizard.pages.p2_case.

if nargin < 1
    gui_visible = {'ieee14','ne39'};
end

% plot_results is OPT-IN.  It used to default true here, which made every
% solve_case run pop figure windows over the screen (the owner: "ทำไมมันโชว์
% น่ารำคาญ").  Every other caller already treats it as opt-in -- +examples/
% turn it ON deliberately, and +pfapp/common_options, +ibr/* and every test
% pass false -- so the catalog was the one outlier.  Ask for plots by name:
%   solve_case('analysis','ts','case','ne39','options',struct('plot_results',true))
base=struct('t_end',15,'dt',0.01,'t_fault',1,'t_clear',1.1, ...
    'Zf',1i*0.1,'method','trapezoidal', ...
    'stepper','fixed', ...
    'corrector_mode','adaptive','corrector_iter',[], ...
    'corrector_abs_tol',1e-10,'corrector_rel_tol',1e-8, ...
    'max_corrector_iter',10,'corrector_failure','error', ...
    'verbose',true,'plot_results',false,'model','classical');

c=[net('ieee5','IEEE 5-bus',@cases.case_ieee5bus,3,base); ...
   net('ieee14','IEEE 14-bus',@cases.case_ieee14bus,4,base); ...
   net('ieee300','IEEE 300-bus',@cases.case_ieee300bus,3,base); ...
   net('ne39','IEEE 39-bus New England (10-machine)',@cases.case_ne39,16,base); ...
   net('rts24','IEEE RTS 24-bus (RTS-1996)',@cases.case_ieee_rts24_pgaz,15,base); ...
   net('padiyar_two_area','Padiyar two-area model 1.1 + AVR',@cases.case_padiyar_two_area_4m_avr,3,base); ...
   net('kundur_two_area','Kundur two-area classical',@cases.case_kundur_two_area_classical,8,base); ...
   net('matpower14','MATPOWER case14',@cases.case_matpower6_case14,4,base); ...
   net('case9','WSCC/MATPOWER case9',@cases.case_matpower6_case9,7,base); ...
   net('matpower30','MATPOWER IEEE 30-bus',@cases.case_matpower_ieee30bus,30,base); ...
   net('saadat67','Saadat Example 6.7',@cases.case_saadat_example_6_7,3,base); ...
   net('saadat68','Saadat Example 6.8',@cases.case_saadat_example_6_8,3,base); ...
   net('ieee30','IEEE 30-bus (Saadat)',@cases.case_saadat_ieee30bus,30,base); ...
   net('template','N-bus case template',@cases.case_template_nbus,3,base); ...
   net('kundur','Kundur Example 12.6',@cases.kundur_ex126_book_case,8,base)];

% This case has published sixth-order dynamics; select operational EMF6 by
% default.  Users can still request its classical model explicitly.
pk=find(strcmp({c.id},'padiyar_two_area'),1);
c(pk).sssa_options=struct('model','padiyar_1_1_avr');
c(pk).ts_options.model='padiyar_1_1_avr';
c(pk).ts_options.dt=0.005; c(pk).ts_options.t_end=3;
c(pk).ts_options.Zf=1i*0.5;

kk=find(strcmp({c.id},'kundur'),1);
c(kk).sssa_options=struct('model','emf6');
c(kk).ts_options.model='emf6';
c(kk).ts_options.corrector_mode='fixed';
c(kk).ts_options.corrector_iter=3;

% Mark, do not remove.  A hidden entry is still resolvable by id -- see the
% header.  Fail closed if the offer list names something that does not exist.
for k=1:numel(c)
    c(k).gui_visible=any(strcmp(c(k).id,gui_visible));
end
missing=setdiff(gui_visible,{c.id});
if ~isempty(missing)
    error('cases:network_case_catalog:unknownGuiCase', ...
        'gui_visible names case id(s) not in the catalog: %s.',strjoin(missing,', '));
end
end

function s=net(id,label,loader,fault_bus,base)
t=base; t.fault_bus=fault_bus;
s=struct('id',id,'label',label,'loader',loader, ...
    'pf_options',struct(),'sssa_options',struct('model','classical'), ...
    'ts_options',t);
end
