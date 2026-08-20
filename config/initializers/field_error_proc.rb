# By default Rails wraps every field that has a validation error in
# `<div class="field_with_errors">`. That extra wrapper breaks layouts
# whose CSS depends on the input being a direct child of its container
# (e.g. the auth-shell .input.field uses `height: 100%` on the input,
# which collapses to the line-height when the wrapper interposes a div).
#
# Error styling is already handled explicitly: the form views add
# `input-error` to the label when `resource.errors[:field].any?`, and
# devise/shared/_error_messages renders the summary banner. The default
# wrapper adds nothing on top of that, so we make field_error_proc a
# passthrough.
ActionView::Base.field_error_proc = proc { |html_tag, _instance| html_tag.html_safe }
