# syno_manage_accounts

Manage Synology DSM user accounts over a **pre-provisioned SSH forced-command
transport**, rather than the DSM HTTP API.

## Why SSH and not the DSM API

On DSM 7.2, `SYNO.Core.User` `create`/`delete` are reserved for the built-in
`admin` (uid 1024). Every other account — even a member of the `administrators`
group — gets DSM **error 105 (insufficient permission)** on user delete. Since
the built-in `admin` is normally disabled, there is no usable API path for
removing a user. The reliable path is `synouser` as root over SSH.

This role does **not** open root SSH to the NAS. It consumes a capability-narrowed
**forced-command key**: the key can invoke only a single wrapper on the NAS whose
protocol is `retire <username>`. The blast radius of a leaked key is "delete one
non-protected account", not root on the box. **Provisioning that transport
(deploy account, wrapper, scoped sudoers, key) is the caller's responsibility —
this role only consumes it.**

## What the role does

| `state`   | Behaviour                                                                 |
|-----------|---------------------------------------------------------------------------|
| `absent`  | Runs `retire <name>` over the transport and maps the wrapper's exit code. |
| `present` | **No-op.** This transport cannot create accounts; a declared-present user is simply left untouched and the run converges green. Use a create-capable role (e.g. `syno_add_accounts`) to add accounts. |

### Exit-code mapping (`state: absent`)

The role expects the NAS-side wrapper to return these codes and maps them so that
runs are **idempotent** and failures are **loud**:

| Wrapper exit | Meaning                     | Result                              |
|--------------|-----------------------------|-------------------------------------|
| `0`          | User existed, now deleted   | `changed`                           |
| `4`          | No such user (already gone) | **OK, `changed=0`** (idempotent)    |
| `3`          | Protected account refused   | **fails loudly**                    |
| `2`          | Bad/arbitrary command       | **fails loudly** (transport misuse) |
| other        | e.g. SSH/connection failure | **fails loudly**                    |

### In-role protected-account denylist (defense in depth)

Before contacting the NAS at all, the role refuses to retire any account on its
denylist — a second line of defence independent of whatever the NAS-side wrapper
enforces. The built-in generic set (`admin`, `root`, `guest`, `anonymous`) is
**always** enforced; callers add site-specific names via `syno_protected_users`
(the two lists are merged, not replaced).

## Role variables

| Variable                       | Required | Default                               | Description                                                                 |
|--------------------------------|----------|---------------------------------------|-----------------------------------------------------------------------------|
| `syno_users`                   | yes      | —                                     | List of `{ name, state }`. `state` is `present` (default) or `absent`.      |
| `syno_ssh_host`                | yes      | —                                     | Host the forced-command key connects to.                                    |
| `syno_ssh_port`                | no       | `22`                                  | SSH port.                                                                    |
| `syno_deploy_user`             | yes      | —                                     | Deploy account the key authenticates as.                                    |
| `syno_ssh_private_key`         | yes      | —                                     | Contents of the forced-command private key. Staged to a `0600` temp file for the run and removed afterwards; never logged. |
| `syno_protected_users`         | no       | `[]`                                  | Extra account names to refuse (merged with the built-in set).               |
| `syno_protected_users_builtin` | no       | `[admin, root, guest, anonymous]`     | The always-on generic denylist. Override only to change the built-in set.   |

### Output

The role sets `syno_manage_accounts_results`: a list of per-account outcomes
`{ name, state, action, changed, rc }` where `action` is `deleted`,
`already_absent`, or `kept`.

## Run location

Like the other roles in this collection, run this from the **control node**
(target `localhost` / `connection: local`); it SSHes out to `syno_ssh_host`.

## Example

```yaml
- name: Retire departed accounts on the NAS
  hosts: localhost
  connection: local
  gather_facts: false
  tasks:
    - name: Manage DSM accounts
      ansible.builtin.include_role:
        name: tafeen.synology.syno_manage_accounts
      vars:
        syno_ssh_host: "{{ dsm_ssh_host }}"
        syno_deploy_user: "{{ dsm_retire_deploy_user }}"
        syno_ssh_private_key: "{{ dsm_retire_ssh_key }}"   # from your secret store
        syno_protected_users: [backupsvc]                  # site-specific extras
        syno_users:
          - { name: alice,   state: present }              # keep (no-op)
          - { name: oldtemp, state: absent }               # retire
```

Secrets (`syno_ssh_private_key`) should come from a secret store (Ansible Vault,
OpenBao/Vault lookup, etc.) — never commit a private key.

## Testing

`tests/test_syno_manage_accounts.yml` is a self-contained suite that needs **no
NAS**: it installs a mock `ssh` (`tests/mocks/mock_ssh.sh`) that returns the
wrapper's exit codes, then asserts the full mapping and the denylist.

```bash
cd tests
ansible-playbook test_syno_manage_accounts.yml
```
