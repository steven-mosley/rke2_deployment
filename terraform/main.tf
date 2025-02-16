###############################################################################
# TERRAFORM SETTINGS
###############################################################################
terraform {
  required_version = ">= 1.3.0"

  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.8.1"
    }
    ignition = {
      source  = "community-terraform-providers/ignition"
      version = "2.3.5"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.4.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "3.2.1"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

provider "null" {}
provider "local" {}

###############################################################################
# DATA: SSH KEY & IGNITION USER
###############################################################################
data "local_file" "ssh_key" {
  filename = pathexpand("~/.ssh/id_ed25519.pub")
}

data "ignition_user" "core" {
  name                = "core"
  ssh_authorized_keys = [data.local_file.ssh_key.content]
}

###############################################################################
# VARIABLES
###############################################################################
variable "control_plane_count" {
  type        = number
  default     = 1
  description = "Number of control plane nodes to create."
}

variable "worker_count" {
  type        = number
  default     = 3
  description = "Number of worker nodes to create."
}

variable "fcos_image_path" {
  type        = string
  default     = "/var/lib/libvirt/images/rke2/fedora-coreos-41.20250117.3.0-qemu.x86_64.qcow2"
  description = "Path to the Fedora CoreOS QCOW2 base image."
}

###############################################################################
# STORAGE POOL
###############################################################################
resource "libvirt_pool" "rke2" {
  name = "rke2"
  type = "dir"
  target {
    path = "/var/lib/libvirt/images/rke2"
  }
}

###############################################################################
# FIX DIRECTORY PERMISSIONS
###############################################################################
resource "null_resource" "fix_rke2_permissions" {
  depends_on = [libvirt_pool.rke2]

  provisioner "local-exec" {
    command = <<-EOT
      sudo chown root:libvirt /var/lib/libvirt/images/rke2
      sudo chmod 770 /var/lib/libvirt/images/rke2
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
}

###############################################################################
# PREPARE THE FEDORA COREOS IMAGE
###############################################################################
resource "null_resource" "prepare_fcos_image" {
  depends_on = [null_resource.fix_rke2_permissions]

  provisioner "local-exec" {
    command = <<-EOT
      if [ ! -f "${var.fcos_image_path}" ]; then
        echo "QCOW2 file not found. Downloading Fedora CoreOS..."
        docker run --pull=always --rm \
          -v "/var/lib/libvirt/images/rke2:/data" \
          -w /data \
          quay.io/coreos/coreos-installer:release \
          download -s stable -p qemu -f qcow2.xz --decompress
      else
        echo "QCOW2 file already exists: ${var.fcos_image_path}"
      fi

      # Ensure the QCOW2 file is owned by root:libvirt and group-readable
      sudo chown root:libvirt "${var.fcos_image_path}"
      sudo chmod 660 "${var.fcos_image_path}"
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
}

###############################################################################
# NODE NAMES
###############################################################################
locals {
  control_nodes = [for i in range(var.control_plane_count) : "Mercury-${i + 1}"]
  worker_nodes  = [for i in range(var.worker_count) : "Io-${i + 1}"]
}

###############################################################################
# VOLUMES: Each node gets its own disk
###############################################################################
resource "libvirt_volume" "control_disk" {
  for_each  = toset(local.control_nodes)
  depends_on = [null_resource.prepare_fcos_image]  # <-- Important
  name     = "${each.key}.qcow2"
  pool     = libvirt_pool.rke2.name
  source   = var.fcos_image_path
  format   = "qcow2"

  # lifecycle {
  #   prevent_destroy = true
  # }
}

resource "libvirt_volume" "worker_disk" {
  for_each  = toset(local.worker_nodes)
  depends_on = [null_resource.prepare_fcos_image]  # <-- Important
  name     = "${each.key}.qcow2"
  pool     = libvirt_pool.rke2.name
  source   = var.fcos_image_path
  format   = "qcow2"

  # lifecycle {
  #   prevent_destroy = true
  # }
}

###############################################################################
# VIRTUAL NETWORK
###############################################################################
resource "libvirt_network" "rke_network" {
  name      = "rke_network"
  mode      = "nat"
  domain    = "rke.local"
  addresses = ["192.168.124.0/24"]
}

###############################################################################
# OUTPUT: Control Plane IPs
###############################################################################
output "control_plane_ips" {
  description = "List of IP addresses for all control-plane nodes."
  value       = [for k, v in libvirt_domain.control : v.network_interface[0].addresses[0]]
}

locals {
  primary_control_ip = element(
    [for k, v in libvirt_domain.control : v.network_interface[0].addresses[0]],
    0
  )
}

###############################################################################
# HOSTNAME CONFIG VIA IGNITION
###############################################################################
data "ignition_file" "control_hostname" {
  for_each = toset(local.control_nodes)
  path     = "/etc/hostname"
  mode     = "0644"
  content {
    content = each.key
  }
}

data "ignition_file" "worker_hostname" {
  for_each = toset(local.worker_nodes)
  path     = "/etc/hostname"
  mode     = "0644"
  content {
    content = each.key
  }
}

###############################################################################
# IGNITION SYSTEMD UNITS (CONTROL PLANE)
###############################################################################
data "ignition_systemd_unit" "control_rke2_install" {
  for_each = toset(local.control_nodes)
  name     = "rke2-server-install.service"
  enabled  = true
  content  = <<-EOT
    [Unit]
    Description=Install RKE2 Server
    After=network-online.target
    Wants=network-online.target
    ConditionPathExists=!/var/lib/rancher/rke2/rke2-server-install.done

    [Service]
    Type=oneshot
    Environment="INSTALL_RKE2_METHOD=tar"
    Environment="INSTALL_RKE2_TYPE=server"
    ExecStart=/bin/sh -c 'curl -sfL https://get.rke2.io | sh - && systemctl enable rke2-server.service && systemctl start rke2-server.service && touch /var/lib/rancher/rke2/rke2-server-install.done'
    RemainAfterExit=yes

    [Install]
    WantedBy=multi-user.target
  EOT
}

###############################################################################
# IGNITION SYSTEMD UNITS (AGENT)
###############################################################################
data "ignition_systemd_unit" "worker_rke2_install" {
  for_each = toset(local.worker_nodes)
  name     = "rke2-agent-install.service"
  enabled  = true
  content  = <<-EOT
    [Unit]
    Description=Install RKE2 Agent
    After=network-online.target
    Wants=network-online.target
    ConditionPathExists=!/var/lib/rancher/rke2/rke2-agent-install.done

    [Service]
    Type=oneshot
    Environment="INSTALL_RKE2_METHOD=tar"
    Environment="INSTALL_RKE2_TYPE=agent"
    ExecStart=/bin/sh -c 'curl -sfL https://get.rke2.io | sh - && systemctl enable rke2-agent.service && systemctl start rke2-agent.service && touch /var/lib/rancher/rke2/rke2-agent-install.done'
    RemainAfterExit=yes

    [Install]
    WantedBy=multi-user.target
  EOT
}

###############################################################################
# IGNITION CONFIG FOR CONTROL PLANE
###############################################################################
data "ignition_config" "control_plane_ignition" {
  for_each = toset(local.control_nodes)
  users    = [data.ignition_user.core.rendered]
  systemd  = [data.ignition_systemd_unit.control_rke2_install[each.key].rendered]
  files    = [data.ignition_file.control_hostname[each.key].rendered]
}

resource "libvirt_ignition" "control_plane_ignition" {
  for_each = toset(local.control_nodes)
  name     = "${each.key}.ign"
  content  = data.ignition_config.control_plane_ignition[each.key].rendered
}

###############################################################################
# RETRIEVE CONTROL PLANE TOKEN
###############################################################################
locals {
  ssh_opts = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
}

resource "null_resource" "get_control_token" {
  depends_on = [libvirt_domain.control]

  provisioner "local-exec" {
    command = <<-EOT
      # Wait for the token file to exist
      for i in {1..10}; do
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null core@${local.primary_control_ip} \
          "test -f /var/lib/rancher/rke2/server/token" && break || sleep 10
      done

      # Use sudo to read it, since it's owned by root:root with 600 permissions
      ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null core@${local.primary_control_ip} \
        "sudo cat /var/lib/rancher/rke2/server/token" > ${path.module}/control_token.txt
    EOT
    interpreter = ["/bin/bash", "-c"]
  }
}

data "local_file" "control_token" {
  filename   = "${path.module}/control_token.txt"
  depends_on = [null_resource.get_control_token]
}

###############################################################################
# IGNITION CONFIG FOR WORKER NODES
###############################################################################
data "ignition_file" "worker_rke2_config" {
  for_each = toset(local.worker_nodes)
  path     = "/etc/rancher/rke2/config.yaml"
  mode     = "0644"
  content {
    content = <<-EOT
      token: ${data.local_file.control_token.content}
      server: https://${local.primary_control_ip}:9345
    EOT
  }
}

data "ignition_config" "worker_ignition" {
  for_each = toset(local.worker_nodes)
  systemd  = [data.ignition_systemd_unit.worker_rke2_install[each.key].rendered]
  files    = [
    data.ignition_file.worker_hostname[each.key].rendered,
    data.ignition_file.worker_rke2_config[each.key].rendered
  ]
  users    = [data.ignition_user.core.rendered]
}

resource "libvirt_ignition" "worker_ignition" {
  for_each = toset(local.worker_nodes)
  name     = "${each.key}.ign"
  content  = data.ignition_config.worker_ignition[each.key].rendered
}

###############################################################################
# DOMAIN RESOURCES (VMs)
###############################################################################
resource "libvirt_domain" "control" {
  for_each        = toset(local.control_nodes)
  name            = each.key
  memory          = 4096
  vcpu            = 2
  coreos_ignition = libvirt_ignition.control_plane_ignition[each.key].id

  disk {
    volume_id = libvirt_volume.control_disk[each.key].id
  }

  network_interface {
    network_name   = libvirt_network.rke_network.name
    wait_for_lease = true
  }

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }
}

resource "libvirt_domain" "worker" {
  for_each   = toset(local.worker_nodes)
  depends_on = [libvirt_domain.control]
  name       = each.key
  memory     = 2048
  vcpu       = 2
  coreos_ignition = libvirt_ignition.worker_ignition[each.key].id

  disk {
    volume_id = libvirt_volume.worker_disk[each.key].id
  }

  network_interface {
    network_name   = libvirt_network.rke_network.name
    wait_for_lease = true
  }

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }
}
