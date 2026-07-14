#!/usr/bin/env bash
# tests/fm-treehouse-lease-smoke.test.sh - real treehouse smoke test for the
# durable worktree lease bin/fm-spawn.sh now acquires for every ordinary
# ship/scout crewmate (data/dup-dispatch-investigate/report.md): plain
# `treehouse get` was only a transient reservation tracked by scanning for a
# live process rooted in the worktree, not durable persistent-state tracking,
# which was a real duplicate-dispatch risk under a single-slot pool.
# fm-spawn.sh now runs `treehouse get --lease --lease-holder <task-id>` from
# its OWN process (bin/fm-spawn.sh's treehouse block) - the exact pattern
# bin/fm-home-seed.sh's acquire_treehouse_home already used for secondmate
# homes - then sends the crewmate's pane a `cd` into the leased path.
#
# This suite drives the REAL treehouse CLI (skips if not installed), like
# tests/fm-backend-tmux-smoke.test.sh drives a real tmux: fake wiring proves
# fm-spawn.sh/fm-teardown.sh construct the right command, but only a real
# binary proves the lease is actually visible in `treehouse status` and
# actually released by the exact `treehouse return --force <path>` teardown
# already runs (bin/fm-teardown.sh's teardown_treehouse_return) - no
# teardown-side change was needed; return releases a lease exactly like a
# transient reservation.
set -u

fail() { printf 'not ok - %s\n' "$1" >&2; cleanup_all; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }
assert_contains_local() {  # <haystack> <needle> <msg>
  case "$1" in
    *"$2"*) : ;;
    *) fail "$3"$'\n'"--- got ---"$'\n'"$1" ;;
  esac
}
assert_not_contains_local() {  # <haystack> <needle> <msg>
  case "$1" in
    *"$2"*) fail "$3"$'\n'"--- got ---"$'\n'"$1" ;;
  esac
}

command -v treehouse >/dev/null 2>&1 || { echo "skip: treehouse not found"; exit 0; }

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/fm-treehouse-lease-smoke.XXXXXX")
ID="treehouseleasesmoke1"
LEASED_WT=

# treehouse's own pool bookkeeping (the per-project dir under ~/.treehouse plus
# its state.json) outlives a `return`, by design, so this scratch pool - unique
# to this run via the mktemp'd project path's hash - is removed directly rather
# than left as permanent litter in the captain's real ~/.treehouse.
cleanup_all() {
  [ -n "$LEASED_WT" ] && (cd "$TMP_ROOT/proj" 2>/dev/null && treehouse return --force "$LEASED_WT" >/dev/null 2>&1)
  [ -n "$LEASED_WT" ] && rm -rf "$(dirname "$(dirname "$LEASED_WT")")"
  rm -rf "$TMP_ROOT"
}
trap cleanup_all EXIT

PROJ="$TMP_ROOT/proj"
mkdir -p "$PROJ"
git -C "$PROJ" init -q
printf '# scratch\n' > "$PROJ/README.md"
git -C "$PROJ" add README.md
git -C "$PROJ" -c user.name='Firstmate Tests' -c user.email='tests@example.invalid' commit -qm initial

# --- acquire exactly the invocation bin/fm-spawn.sh's treehouse block runs --

LEASED_WT=$( (cd "$PROJ" && treehouse get --lease --lease-holder "$ID") 2>/dev/null )
[ -n "$LEASED_WT" ] || fail "treehouse get --lease --lease-holder did not report a worktree path"
[ -d "$LEASED_WT" ] || fail "leased worktree path does not exist: $LEASED_WT"
pass "real treehouse: get --lease --lease-holder prints a worktree path"

wt_top=$(git -C "$LEASED_WT" rev-parse --show-toplevel 2>/dev/null || true)
[ -n "$wt_top" ] || fail "leased worktree is not a git worktree"
proj_top=$(git -C "$PROJ" rev-parse --show-toplevel 2>/dev/null || true)
[ "$wt_top" != "$proj_top" ] || fail "leased worktree resolved to the primary project checkout (not isolated)"
pass "real treehouse: the leased worktree is a genuine, isolated worktree of the project"

# --- the lease must be durably visible in `treehouse status`, holder recorded

STATUS_OUT=$(cd "$PROJ" && treehouse status 2>&1)
assert_contains_local "$STATUS_OUT" "leased" \
  "treehouse status did not report the acquired worktree as leased"
assert_contains_local "$STATUS_OUT" "held by $ID" \
  "treehouse status did not record the lease holder as the task id"
pass "real treehouse: status shows the worktree durably leased to the task id"

# --- released exactly the way bin/fm-teardown.sh's teardown_treehouse_return
# releases it: `treehouse return --force <path>`, run from the project dir
# (teardown_treehouse_return's own convention - treehouse resolves the pool
# from the working directory).

RETURN_OUT=$(cd "$PROJ" && treehouse return --force "$LEASED_WT" 2>&1)
status=$?
[ "$status" -eq 0 ] || fail "treehouse return --force failed for the leased worktree"$'\n'"$RETURN_OUT"
pass "real treehouse: return --force cleanly releases a --lease-acquired worktree (exit 0)"

STATUS_AFTER=$(cd "$PROJ" && treehouse status 2>&1)
assert_not_contains_local "$STATUS_AFTER" "held by $ID" \
  "treehouse status still shows the task id holding a lease after return"
assert_not_contains_local "$STATUS_AFTER" "leased" \
  "treehouse status still reports a leased worktree after return"
pass "real treehouse: after return, the pool slot is free (no leased/held-by entry) - the same release path bin/fm-teardown.sh already runs needs no change for leased worktrees"

cleanup_all
trap - EXIT
