# tmux-ai bindings for ai-popup
#
# Source from ~/.tmux.conf (or the file of your choice):
#
#     bind-key -T prefix g run-shell "tmux source-file ~/.config/tmux-ai/tmux-ai.tmux"
#     ...or simply add the two lines below to ~/.tmux.conf
#
# The generated command is typed into the pane that was current before
# the popup opened (via #{pane_id} + `tmux send-keys -l`), so it lands
# in the shell's own readline line — fully editable, run with Enter.

# Open the AI popup: type a request, Enter to generate, Enter to insert.
bind-key -T prefix g display-popup -w 70% -h 30% -E \
  "/path/to/ai-popup -t '#{pane_id}'"

# Non-tmux users can run ai-popup directly; it prints the command when
# TMUX is unset.
