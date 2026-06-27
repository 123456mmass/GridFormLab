function reset_axes_state(ax)
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
