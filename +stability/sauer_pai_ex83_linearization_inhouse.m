function out = sauer_pai_ex83_linearization_inhouse()
%SAUER_PAI_EX83_LINEARIZATION_INHOUSE In-house Sauer-Pai Example 8.3 model plugin.
% This is only a benchmark-specific data wrapper. The analytical equations
% are implemented in stability.sauer_pai_linearization, which accepts a case
% struct and is reusable for other systems using the same model family.

out = stability.sauer_pai_linearization(cases.sauer_pai_ex83_case());
end
