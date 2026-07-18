function cancel(fig)
%CANCEL  Cancel the wizard: clear the result and close the figure.
app = fig.UserData.app;
app.last_result = [];
fig.UserData.app = app;
delete(fig);
end
