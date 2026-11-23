# inert-text.awk — the shell command without the text that cannot run, so that
# block-dangerous-bash.sh does not take it for a command.
#
# It knows only the two forms an assistant writes every day, and only when the
# command starts with them, on its first line, with nothing before (a quoted
# message may also follow &&, || or ; after plain text):
#
#   1. A commit message:
#        git commit [flags] -m "…"           the message, when it has no $,
#                                            backtick or backslash, becomes Q;
#        git commit [flags] -m "$(cat <<'EOF'
#        …
#        EOF
#        )"                                  the heredoc body goes.
#   2. A file written with a heredoc, when the command ends with it:
#        cat > path <<'EOF'
#        …
#        EOF                                 the body goes, unless the path is a
#                                            git hook, a git or MCP configuration,
#                                            under .claude/, .husky/ or .github/,
#                                            or a shell startup file: those run
#                                            later.
#
# Anything else, or any doubt, leaves the command as it came. So do:
#   - a body line that starts with the delimiter, as in "EOF)": bash may close
#     the heredoc there;
#   - in a commit message heredoc, a ")" in the body: bash 3.2 closes the $(
#     at an unpaired one, and what follows runs;
#   - a commit with -e or --edit: git hands the message to the editor, which
#     may run it.
#
# Run with LC_ALL=C, so that a non-ASCII character is only a byte.

{ line[NR] = $0 }

# body_end(delim, no_paren) → the line that closes a heredoc opened on line 1,
# or 0. With no_paren, a ")" in the body gives 0.
function body_end(delim, no_paren,    j) {
  for (j = 2; j <= NR; j++) {
    if (line[j] == delim) return j
    if (index(line[j], delim) == 1) return 0
    if (no_paren && index(line[j], ")")) return 0
  }
  return 0
}

# edits(s) → whether s has -e or --edit, alone or in a group of short flags.
function edits(s) {
  return s ~ /(^|[ \t])(--edit|-[A-Za-z]*e[A-Za-z]*)([ \t;&|]|$)/
}

# up_to_separator(s) → s up to the end of its command: ;, &, | or a new line.
function up_to_separator(s) {
  sub(/[;&|\n].*/, "", s)
  return s
}

function print_without(from, to,    j) {
  for (j = 1; j <= NR; j++) if (j < from || j > to) printf "%s%s", line[j], (j < NR ? "\n" : "")
}

END {
  first = line[1]
  flags = "([ \t]+-[-A-Za-z0-9=]+)*"
  commit = "^[ \t]*git[ \t]+commit" flags "[ \t]+(-[A-Za-z]*m|--message=?)[ \t]*\""
  quoted_delim = "<<[ \t]*'[A-Za-z0-9_]+'[ \t]*$"

  # 1. Commit message from a heredoc.
  if (first ~ (commit "\\$\\(cat[ \t]+" quoted_delim)) {
    delim = first; sub(/.*<<[ \t]*'/, "", delim); sub(/'.*/, "", delim)
    j = body_end(delim, 1)
    if (j && j < NR && line[j + 1] ~ /^[ \t]*\)"/ \
        && !edits(first) && !edits(up_to_separator(line[j + 1]))) {
      print_without(2, j - 1); exit
    }
  }

  # 1. Commit message in quotes. Here git commit can also follow &&, || or ; when
  #    what comes before it is plain: no quote, $, backtick, backslash, <, #,
  #    parenthesis or brace.
  text = line[1]; for (j = 2; j <= NR; j++) text = text "\n" line[j]
  after_plain = "^([^\"'`$\\\\<#(){}\n]*(&&|\\|\\||;)[ \t]*)?"
  if (match(text, after_plain substr(commit, 2))) {
    head = substr(text, 1, RSTART + RLENGTH - 2)
    rest = substr(text, RSTART + RLENGTH)
    close_at = index(rest, "\"")
    if (close_at && substr(rest, 1, close_at - 1) !~ /[$`\\]/ \
        && !edits(head) && !edits(up_to_separator(substr(rest, close_at + 1)))) {
      printf "%s", head "Q" substr(rest, close_at + 1); exit
    }
  }

  # 2. A file written with a heredoc.
  if (first ~ ("^[ \t]*cat[ \t]*>[ \t]*[A-Za-z0-9_./-]+[ \t]+" quoted_delim)) {
    path = first; sub(/^[ \t]*cat[ \t]*>[ \t]*/, "", path); sub(/[ \t].*/, "", path)
    runs_later = path ~ /(^|\/)\.git\// || path ~ /(^|\/)\.claude\// \
      || path ~ /(^|\/)\.(husky|github)\// || path ~ /(^|\/)\.(gitconfig|mcp\.json|envrc)$/ \
      || path ~ /(^|\/)\.(bashrc|bash_profile|bash_login|bash_logout|profile|zshrc|zprofile|zshenv|zlogin|zlogout)$/
    delim = first; sub(/.*<<[ \t]*'/, "", delim); sub(/'.*/, "", delim)
    j = body_end(delim, 0)
    empty_after = 1
    for (k = j + 1; k <= NR; k++) if (line[k] ~ /[^ \t]/) empty_after = 0
    if (!runs_later && j && empty_after) { print_without(2, j - 1); exit }
  }

  printf "%s", text
}
