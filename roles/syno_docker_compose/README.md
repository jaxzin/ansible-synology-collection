# tafeen.synology.syno_docker_compose

Converge one or more **docker-compose projects** on a Synology host (the Docker /
Container Manager package). Deploys/updates a project (`docker compose up -d`) or
tears it down (`down`), from a compose file kept in the *consumer* repo.

Runs over the collection's SSH transport and calls Synology's bundled Docker CLI
(`/usr/local/bin/docker`, compose v2 plugin) by absolute path — it is not on a
non-interactive SSH `PATH`.

> **No `become`.** Synology authorizes docker by **docker-group membership**, not
> root. The connecting user must be in the `docker` group; do not add `become`
> (Synology `sudo` needs a password that breaks a forced-command SSH transport).

## Variables

| var | required | default | meaning |
|---|---|---|---|
| `syno_compose_projects` | yes | — | list of project dicts (below) |
| `syno_docker_bin` | no | `/usr/local/bin/docker` | Synology docker CLI path |

Each `syno_compose_projects` item:

| key | required | default | meaning |
|---|---|---|---|
| `name` | yes | — | compose project name (and default dir leaf) |
| `compose_src` | yes | — | compose file in the consumer's `files/`; copied to `<path>/docker-compose.yml` |
| `path` | no | `/volume1/docker/<name>` | on-host project directory |
| `state` | no | `present` | `present` → `up -d`; `absent` → `down` |
| `pull` | no | `missing` | image pull policy: `always` \| `missing` \| `never` |
| `env_src` | no | — | `.env` file in the consumer's `files/`; copied to `<path>/.env` (mode 0600) |

## Example

```yaml
- name: Deploy the netboot.xyz menu container
  hosts: nas
  gather_facts: false
  tasks:
    - name: Converge netbootxyz
      ansible.builtin.import_role:
        name: tafeen.synology.syno_docker_compose
      vars:
        syno_compose_projects:
          - name: netbootxyz
            path: /volume1/docker/netbootxyz
            compose_src: files/netbootxyz.docker-compose.yml
            pull: missing
```

## Idempotency

`docker compose up -d` recreates only what changed; the role reports `changed`
when compose emits `Started`/`Recreated`/`Created`/`Pulled`, or when the copied
compose/`.env` file itself changed. A converged project run twice reports
`changed=0`.
