function [ok,decision]=ne39_snapshot_policy(evidence,policy)
%NE39_SNAPSHOT_POLICY แยกเกณฑ์ศึกษาออกจาก strict evidence โดยไม่แก้ evidence.
arguments
    evidence (1,1) struct
    policy (1,1) string {mustBeMember(policy,["strict","observe_voltage"])} = "strict"
end
decision=struct('policy',char(policy),'status','REFUSED', ...
    'strict_status','UNKNOWN','voltage_excursion',false,'production_certified',false);
ok=false;
if ~all(isfield(evidence,{'status','complete','nonvoltage_status','voltage_reference'})) || ...
        ~isequal(evidence.complete,true)
    return;
end
decision.strict_status=evidence.status;
if ~isfield(evidence.voltage_reference,'pass'), return; end
decision.voltage_excursion=~evidence.voltage_reference.pass;
if strcmp(evidence.status,'PASS')
    ok=true; decision.status='STRICT_SNAPSHOT_PASS';
elseif policy=="observe_voltage" && strcmp(evidence.status,'FAIL') && ...
        strcmp(evidence.nonvoltage_status,'PASS') && decision.voltage_excursion
    ok=true; decision.status='STUDY_VOLTAGE_EXCURSION';
end
end
