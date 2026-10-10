function reset_axes_state(ax)
%DEPRECATED (Phase C): superseded by the Studio GUI (+studio/launch.m).
%   Header banner only; behavior unchanged.
%RESET_AXES_STATE Clear a reused GUI axis and restore default linear scales.

cla(ax);
ax.XScale = 'linear';
ax.YScale = 'linear';
ax.XLimMode = 'auto';
ax.YLimMode = 'auto';
ax.XTickMode = 'auto';
ax.YTickMode = 'auto';
hold(ax, 'off');
end
