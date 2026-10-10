function tests = test_case_visibility_contract
%TEST_CASE_VISIBILITY_CONTRACT  Hide from the GUI, do not delete from the registry.
%
%   The owner's decision (2026-09-26): the starter network cases are no longer
%   used and the case-selection GUI must offer only the two production
%   networks, IEEE 14 and the IEEE 39-bus New England system.  The rest were
%   to be HIDDEN, not removed -- the owner chose the non-destructive option
%   precisely so that solve_case, scripts/reporting/ and the TS routing tests
%   keep resolving them by id.
%
%   That choice is only as good as the guard around it.  These tests pin both
%   halves:
%
%     (1) THE OFFER SET.  The network catalog marks exactly 'ieee14' and
%         'ne39' as gui_visible.  Every other catalog entry is hidden.
%     (2) HIDE IS NOT DELETE.  Every hidden entry is STILL discoverable by id
%         through wizard.discover_cases and STILL resolvable through
%         wizard.build_request -- the path solve_case uses.  If someone
%         "simplifies" the catalog by dropping the hidden rows, this fails.
%     (3) THE DISPLAY LAYER IS THE ONLY FILTER.  wizard.discover_cases must
%         return hidden entries too, because build_request, validate_request
%         and dispatch_analysis all resolve through it.  Filtering there would
%         break every hidden case while leaving the GUI looking correct.
%     (4) FAIL CLOSED.  An offer list naming a case id that is not in the
%         catalog must throw cases:network_case_catalog:unknownGuiCase rather
%         than silently offering nothing.
%
%   What is NOT pinned here: the wizard case-selection page's use of the flag.
%   That is a UI surface; tests/test_wizard_ui_smoke.m exercises it end to end
%   and tests/test_wizard_pure_layer.m pins discover_cases' schema.
%
%   See also cases.network_case_catalog, wizard.discover_cases, solve_case.

tests = functiontests(localfunctions);
end

function setupOnce(~)
addpath(fileparts(fileparts(mfilename('fullpath'))));
pf_init_paths();
end

% =========================================================================
function test_the_network_catalog_offers_exactly_the_two_production_cases(tc)
cat = cases.network_case_catalog();
ids = {cat.id};
vis = [cat.gui_visible];

tc.verifyTrue(all(islogical(vis)), ...
    'Every catalog entry must carry a logical gui_visible flag.');
tc.verifyEqual(sort(ids(vis)), {'ieee14','ne39'}, ...
    ['The GUI must offer exactly the two production networks. The owner: ' ...
     '"เคสพวกเริ่มต้นไม่ได้ใช้แล้ว ... ใช้เคสหลักแค่ ieee 14 กับ 39 bus".']);

% The hidden set is the whole rest of the catalog -- asserted by count so a
% newly added entry defaults to hidden rather than silently joining the offer.
tc.verifyEqual(nnz(~vis), numel(cat) - 2, ...
    'Every entry other than ieee14 and ne39 must be hidden.');
end

% =========================================================================
function test_every_hidden_case_is_still_discoverable_by_id(tc)
% The "hide is not delete" half.  wizard.discover_cases is the single
% resolution list behind build_request/validate_request/dispatch_analysis, so
% a hidden entry that leaves it is a case that solve_case can no longer run.
cat = cases.network_case_catalog();
hidden = cat(~[cat.gui_visible]);
tc.verifyNotEmpty(hidden, 'This test needs at least one hidden entry.');

for analysis = {'pf','sssa','ts'}
    r = wizard.discover_cases(analysis{1});
    got = {r.id};
    for k = 1:numel(hidden)
        tc.verifyTrue(any(strcmp(got, hidden(k).id)), ...
            sprintf('Hidden case "%s" must remain discoverable for analysis "%s".', ...
            hidden(k).id, analysis{1}));
    end
end
end

% =========================================================================
function test_every_hidden_case_still_resolves_through_the_solve_case_path(tc)
% resolve() is what the UI does; solve_case goes further and calls
% wizard.build_request.  Both must still accept a hidden id, because
% scripts/reporting/generate_padiyar_two_area_report.m runs a hidden case to
% produce a live deliverable document.
cat = cases.network_case_catalog();
hidden = cat(~[cat.gui_visible]);

for k = 1:numel(hidden)
    for analysis = {'pf','ts'}
        tc.verifyWarningFree(@() wizard.build_request(analysis{1}, hidden(k).id), ...
            sprintf('build_request must still accept hidden case "%s" for "%s".', ...
            hidden(k).id, analysis{1}));
    end
end
end

% =========================================================================
function test_the_offer_set_is_a_filter_not_a_registry_trim(tc)
% discover_cases returns hidden entries with gui_visible=false.  If it started
% omitting them, tests above would still pass on 'pf' only by accident, so the
% negative form is asserted directly.
r = wizard.discover_cases('pf');
tc.verifyTrue(any(~[r.gui_visible]), ...
    ['wizard.discover_cases must return the hidden entries flagged false, ' ...
     'not omit them: build_request resolves by id through this list.']);
tc.verifyTrue(any(strcmp({r.id}, 'matpower14')), ...
    'A representative hidden starter case must still be in the list.');
tc.verifyTrue(any(strcmp({r.id}, 'padiyar_two_area')), ...
    'The Padiyar two-area case must still be in the list (it backs a report).');
end

% =========================================================================
function test_an_offer_list_naming_a_missing_case_fails_closed(tc)
% Fail closed on a typo'd offer list: a name that resolves to nothing must
% throw its own identifier, never leave the GUI silently empty.  The optional
% argument exists only to make this reachable.
tc.verifyError(@() cases.network_case_catalog({'ieee14','no_such_case'}), ...
    'cases:network_case_catalog:unknownGuiCase');
% The default must still be the production pair.
cat = cases.network_case_catalog();
tc.verifyEqual(sort({cat([cat.gui_visible]).id}), {'ieee14','ne39'});
end
