# Ansible Collection - tafeen.synology

Synology setup automation, current version was tested on DSM 7.2

Examples of usage:

1. Add accounts
```
---
- name: Provision synology server
  hosts: syno
  become: true
  tasks:
    - name: Setup Accounts
      ansible.builtin.import_role:
        name: tafeen.syno_add_accounts
      vars:
        syno_accounts:
          - name: daniel
            password: "<here goes password>"
          - name: john
            password: "<here goes password>"

```

2. Add Shares
```
- name: Provision synology server
  hosts: syno
  become: true
  tasks:
    - name: Setup Shares
      ansible.builtin.import_role:
        name: tafeen.syno_add_shares
      vars:
        syno_shares:
          - name: media
            description: MEDIA Share
            path: /volume3/media
            recycle: true
            rights:
              RO:
                - daniel
              RW: 
                - john
```

3.  Install packages
```
- name: Provision synology server
  hosts: syno
  become: true
  tasks:
    - name: Setup packages
      ansible.builtin.import_role:
        name: tafeen.syno_pkg_install
      vars:
        syno_upgrade_packages: true
        syno_packages:
            - Docker
            - FileStation
```

4. Setup crontab
```
- name: Provision synology server
  hosts: syno
  become: true
  tasks:
    - name: Setup crontab
      ansible.builtin.import_role:
        name: tafeen.syno_pkg_install
      vars:
        hour: "{{ item.hour }}"
        weekday: "{{ item.weekday }}"
        job: "{{ item.job }}"
      with_items:
        - hour: 10
          weekday: 1
          job: "/bin/do_something.sh"
```

5. Manage (retire) accounts over SSH

`syno_manage_accounts` removes DSM accounts (`state: absent`) via a pre-provisioned
SSH forced-command transport, because DSM's `SYNO.Core.User` delete is blocked
(error 105) for every account except the built-in `admin`. `state: present` is a
no-op (this transport cannot create accounts). Runs from the control node and
SSHes out to the NAS. See [roles/syno_manage_accounts/README.md](roles/syno_manage_accounts/README.md).

```
- name: Retire departed accounts on the NAS
  hosts: localhost
  connection: local
  tasks:
    - name: Manage DSM accounts
      ansible.builtin.include_role:
        name: tafeen.synology.syno_manage_accounts
      vars:
        syno_ssh_host: nas.example.lan
        syno_deploy_user: dsm-retire
        syno_ssh_private_key: "{{ lookup('env', 'DSM_RETIRE_SSH_KEY') }}"
        syno_users:
          - { name: alice,   state: present }   # keep (no-op)
          - { name: oldtemp, state: absent }    # retire
```