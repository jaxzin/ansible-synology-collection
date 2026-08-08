#!/usr/bin/env bash
# Mock `ssh` for the tafeen.synology.syno_manage_accounts test suite.
#
# It stands in for a real SSH connection to a NAS-side forced-command wrapper.
# It ignores connection args (-i, -o, user@host) and looks only at the final
# argument, which is the remote command the role sends: "retire <username>". It
# then returns the SAME exit codes such a wrapper returns, so the role's
# exit-code -> outcome mapping can be tested without a NAS:
#
#   0  deleted            (user existed, now removed)   -> changed
#   2  bad/arbitrary cmd  (not exactly "retire <user>") -> FAIL
#   3  protected account  (wrapper denylist / uid<1026) -> FAIL
#   4  no such user       (already absent)              -> idempotent success
#
# Env (set by the test play):
#   MOCK_SSH_LOG    append each remote command here (proves call / no-call)
#   MOCK_SSH_STATE  dir used to simulate DSM state (deleted users persist)
#
# Reserved test usernames with fixed behaviour:
#   ghost        -> never existed              -> rc 4
#   badcmd       -> force a bad-command result -> rc 2
#   wrapperonly  -> protected by the WRAPPER   -> rc 3 (role denylist does NOT
#                   cover it, so this exercises the role's rc3 mapping)
set -u

log="${MOCK_SSH_LOG:-/dev/null}"
state="${MOCK_SSH_STATE:-}"

# The remote command is the last argument ssh receives.
remote_cmd="${@: -1}"
printf '%s\n' "$remote_cmd" >>"$log"

# Split "retire <username>" — anything else is a bad command.
read -r verb user extra <<<"$remote_cmd"
if [[ "$verb" != "retire" || -z "${user:-}" || -n "${extra:-}" ]]; then
  printf 'mock-wrapper: bad command: %s\n' "$remote_cmd" >&2
  exit 2
fi

# A wrapper's OWN protected denylist (independent of the role's in-role list).
# `wrapperonly` models an account the wrapper protects that the role's default
# denylist does NOT, so the role's rc3 handling is exercised.
case "$user" in
  admin | root | guest | anonymous | wrapperonly)
    printf 'mock-wrapper: refusing protected account %s\n' "$user" >&2
    exit 3
    ;;
esac

case "$user" in
  ghost)
    printf 'mock-wrapper: no such user %s\n' "$user" >&2
    exit 4
    ;;
  badcmd)
    printf 'mock-wrapper: bad command\n' >&2
    exit 2
    ;;
esac

# Simulate state: a user already deleted this run is now "no such user".
if [[ -n "$state" && -f "$state/deleted/$user" ]]; then
  printf 'mock-wrapper: no such user %s\n' "$user" >&2
  exit 4
fi

# Delete it: record state so a second retire is idempotent (rc 4).
if [[ -n "$state" ]]; then
  mkdir -p "$state/deleted"
  : >"$state/deleted/$user"
fi
printf 'mock-wrapper: deleted %s\n' "$user"
exit 0
