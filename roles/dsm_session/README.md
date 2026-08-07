# dsm_session

A small, reusable DSM (Synology DiskStation Manager) **HTTP API session** funnel.
It logs in to DSM's `entry.cgi` Web API, exposes a single task file that every
other API call routes through, and logs out — centralising session hygiene and
error handling so no caller can forget them.

This role does not run *on* the NAS. It drives the DSM Web API over HTTPS from
the control node (`hosts: localhost`, `connection: local`), the same way the
DSM web UI talks to `entry.cgi`.

## Why this exists

The `synoshare` / `synorecycle` CLIs fail on some DSM 7.2 builds (e.g.
`share_is_acl_share.c:49` when adding a shared folder). The DSM HTTP API is the
reliable path. The session transport here is **hard-won**: on DSM 7.2, the
`SYNO.Core.Share` *create* write does **not** honor an `_sid` body param — it
resolves the session from the `id` **cookie** — while reads accept `_sid`. This
role therefore carries the session as a `Cookie: id=<sid>` header on *all* calls
and sends the `X-SYNO-TOKEN` CSRF header from a `enable_syno_token=yes` login.
See `tasks/api_call.yml`'s header for the full saga. **Preserve that behavior.**

## Task entry points

| File | Purpose |
|---|---|
| `tasks/login.yml` | Authenticate; sets `dsm_sid` + `dsm_syno_token` facts. |
| `tasks/api_call.yml` | The funnel every API call routes through (see caller contract in the file header). |
| `tasks/logout.yml` | Best-effort session release; run from an `always:` block. |

## Caller pattern

```yaml
- name: Log in to DSM (sets dsm_sid / dsm_syno_token)
  ansible.builtin.include_role:
    name: tafeen.synology.dsm_session
    tasks_from: login

- name: Resolve the funnel path (sibling role, this collection)
  ansible.builtin.set_fact:
    dsm_api_call: "{{ role_path }}/../dsm_session/tasks/api_call.yml"

- name: Any DSM API call
  ansible.builtin.include_tasks: "{{ dsm_api_call }}"
  vars:
    dsm_call_name: "list shared folders"
    dsm_call_body:
      api: SYNO.Core.Share
      version: "1"
      method: list
# ... work ...
# always:
- name: Release the session
  ansible.builtin.include_role:
    name: tafeen.synology.dsm_session
    tasks_from: logout
  when: dsm_sid is defined
```

## Required variables

`dsm_host` (the NAS address). Optional: `dsm_port` (5001), `dsm_scheme`
(`https`), `dsm_validate_certs` (false), `dsm_api_timeout` (30), `dsm_no_log`
(true). Credentials come from the environment: `DSM_ACCOUNT`, `DSM_PASSWORD`,
and optional `DSM_OTP_CODE` (2FA). The account **must** be in the DSM
`administrators` group.
