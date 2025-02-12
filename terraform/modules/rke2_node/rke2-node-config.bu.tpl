# This is the Butane template that will be rendered for each node. Adjust the SSH key as needed.

variant: fcos
version: 1.6.0
hostname: ${hostname}
passwd:
  users:
    - name: core
      ssh_authorized_keys:
        - "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOR2IHHp5djKZZSfssIXYS1hz1qBFW2z90De4D4B63as astrosteveo@archimedes"
storage:
  disks:
    - device: /dev/disk/by-id/coreos-boot-disk
      wipe_table: false
      partitions:
        - number: 4
          label: root
          size_mib: 8192
          resize: true
        - size_mib: 0
          label: rke2data
  filesystems:
    - path: /var/lib/rke2
      device: /dev/disk/by-partlabel/rke2data
      format: xfs
      options: "noatime"
      with_mount_unit: true
  files:
    - path: /etc/rancher/rke2/config.yaml
      mode: 0644
      contents:
        inline: |
          token: "${token}"
          server: "${server}"
systemd:
  units:
    - name: rke2-install.service
      enabled: true
      contents: |
        [Unit]
        Description=Install RKE2 using tar method (${role})
        After=network-online.target var-lib-rke2.mount
        Wants=network-online.target
        ConditionPathExists=!/var/lib/rancher/rke2/install.done

        [Service]
        Type=oneshot
        Environment="INSTALL_RKE2_METHOD=tar"
        ExecStart=/bin/sh -c 'curl -sfL https://get.rke2.io | sh - && mkdir -p /var/lib/rancher/rke2 && touch /var/lib/rancher/rke2/install.done'
        RemainAfterExit=yes

        [Install]
        WantedBy=multi-user.target

    - name: rke2-${role}-enable.service
      enabled: true
      contents: |
        [Unit]
        Description=Reload systemd and Enable/Start RKE2 ${role^} Service
        After=rke2-install.service
        Wants=rke2-install.service

        [Service]
        Type=oneshot
        ExecStart=/bin/sh -c 'systemctl daemon-reload && systemctl enable --now rke2-${role}.service'
        RemainAfterExit=yes

        [Install]
        WantedBy=multi-user.target

