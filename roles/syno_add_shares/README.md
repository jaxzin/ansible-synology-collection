# syno_add_shares

Manage Synology DSM **shared folders as code** through the DSM HTTP API
(`entry.cgi`), driven from the control node over HTTPS.

## Why the HTTP API (not the CLI)

The original role called `/usr/syno/sbin/synoshare --add`. On DSM 7.2 that fails
with `share_is_acl_share.c:49`, so a share can never be created. The DSM Web API
is the reliable path. All API calls route through the `tafeen.synology.dsm_session`
funnel, which carries the session as a `Cookie: id=<sid>` header (required for the
`SYNO.Core.Share` *create* write on DSM 7.2 — see that role for the full saga).

Because it talks to the API, this role runs against **localhost with
`connection: local`**, not on the NAS via `become`. See `tests/` for a runnable
example.

## Converge safety contract

- **Validate-only by default.** A plain run reads current state and prints a diff
  ("WOULD CREATE / WOULD SET ..."). It changes nothing. Pass `-e converge=true`
  to apply.
- **RULE 1 — create absent, verify existing.** Absent shares are created; existing
  shares are verified. If an existing share is on a different **volume** than
  declared, the run FAILS with a diff — it never moves, deletes, or recreates a
  share.
- **RULE 2 — touch only what is declared.** Rights set only the named users;
  Time Machine adds/removes only this share from the global SMB folder list. Other
  shares, users, and folders are left untouched.
- **Idempotent.** Mutations are gated on `converge=true` AND a real diff, so a
  second converge run reports `changed=0`.
- **Read-back verify.** After applying, the role re-reads the share and asserts
  the managed tuple (name, volume, quota round-trip, rights, Time Machine flag).
- **Secret hygiene.** Credentials POST (never GET); every session/secret-bearing
  task is `no_log`; the session is released in an `always:` block.

## Schema

```yaml
syno_shares:
  - name: "Time Machine Backups"      # required
    description: "Time Machine target for MacBook"   # <= 64 chars
    volume: /volume1                  # volume root; or use legacy `path: /volume1/foo`
    rights:
      RW: [jaxzin]                    # local users, read-write
      RO: [guest]                     # local users, read-only
    recycle: false                    # enable the share recycle bin
    enable_time_machine: true         # SMB Time Machine target (see caveat)
    quota_gb: 4000                    # per-share quota (see caveat)
```

`name`, `description`, `path`/`volume`, `rights.RW`/`rights.RO`, and `recycle`
are backward-compatible with the original CLI role. `enable_time_machine` and
`quota_gb` are new.

### Connection / credentials

Set `dsm_host` (the NAS address); optionally `dsm_port` (5001), `dsm_scheme`
(`https`), `dsm_validate_certs` (false). Credentials come from the environment:
`DSM_ACCOUNT`, `DSM_PASSWORD`, optional `DSM_OTP_CODE`. The account **must** be in
the DSM `administrators` group.

## Unconfirmed field names (confirm on first live run)

This role was built without live NAS credentials. Two DSM fields could not be
verified against a real API and are therefore **isolated, SURFACEd, and
loud-verified** so a wrong guess fails visibly instead of converging green:

| Concern | Assumption | How to confirm / fix |
|---|---|---|
| `quota_gb` unit | `share_quota` is in **GB** (value sent unchanged) | Run 1 prints the stored `share_quota`; compare against the DSM UI's human-readable quota. If off by 1024, the field is in MB — change the one expression in `tasks/manage_share.yml`. |
| Time Machine field | global SMB field is named `tm_folder` | Run 1's SURFACE prints the full `SYNO.Core.FileServ.SMB` get response; set `syno_smb_tm_folder_field` (defaults) to the real field name. Adjust `dsm_api_ver_smb` if the SMB call errors. |

The `SURFACE — ...` debug tasks print the live response shapes on the first run
so these are confirmed, not guessed.

## Example

```yaml
- name: Manage Synology shares over the DSM API
  hosts: localhost
  connection: local
  gather_facts: false
  vars:
    dsm_host: "192.168.10.7"
  tasks:
    - name: Converge shares
      ansible.builtin.include_role:
        name: tafeen.synology.syno_add_shares
      vars:
        syno_shares:
          - name: media
            description: MEDIA Share
            volume: /volume3
            recycle: true
            rights:
              RW: [john]
              RO: [daniel]
```

Run validate-only, then converge:

```bash
export DSM_ACCOUNT=... DSM_PASSWORD=...
ansible-playbook play.yml                 # validate-only (no changes)
ansible-playbook play.yml -e converge=true   # apply
ansible-playbook play.yml -e converge=true   # idempotency: changed=0
```
