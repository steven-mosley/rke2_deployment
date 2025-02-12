terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.8.1"
    }
  }
}

provider "libvirt" {
  # Set your configuration options here.
  # For example, you might set the URI if it's not the default:
  uri = "qemu:///system"
}

# Render the Butane config for the control plane node.
locals {
  cp_butane = templatefile("${path.module}/rke2-node-config.bu.tpl", {
    hostname   = "rke2-cp-01.astronet.local"
    role       = "server"
    token      = var.rke2_token
    server     = ""  # For control plane, you might leave this empty or assign its own URL.
    public_key = var.public_key
  })

  agent_butane = [
    for i in range(var.agent_count) : templatefile("${path.module}/rke2-node-config.bu.tpl", {
      hostname   = format("rke2-agent-%02d.astronet.local", i + 1)
      role       = "agent"
      token      = var.rke2_token
      server     = var.control_plane_url
      public_key = var.public_key
    })
  ]
}

resource "null_resource" "cp_transpile" {
  provisioner "local-exec" {
    command = "echo '${local.cp_butane}' | butane --pretty --strict > ${path.module}/rke2-cp-01.ign"
  }
}

resource "null_resource" "agent_transpile" {
  count = var.agent_count
  provisioner "local-exec" {
    command = "echo '${local.agent_butane[count.index]}' | butane --pretty --strict > ${path.module}/rke2-agent-${format("%02d", count.index + 1)}.ign"
  }
}

resource "libvirt_network" "default" {
  name   = "default"
  mode   = "nat"
  domain = "astronet.local"
}

# Provision the control plane VM.
resource "libvirt_volume" "fcos_cp" {
  name   = "rke2-cp-01.img"
  pool   = "default"
  source = local.full_fcos_image_path
  format = "qcow2"
}

resource "libvirt_domain" "cp" {
  name   = "rke2-cp-01"
  memory = var.control_plane_ram
  vcpu   = var.control_plane_vcpus

  disk {
    volume_id = libvirt_volume.fcos_cp.id
  }

  network_interface {
    network_id = libvirt_network.default.id
  }

  cloudinit = file("${path.module}/rke2-cp-01.ign")
}

# Provision the agent VMs.
resource "libvirt_volume" "fcos_agent" {
  count  = var.agent_count
  name   = format("rke2-agent-%02d.img", count.index + 1)
  pool   = "default"
  source = local.full_fcos_image_path
  format = "qcow2"
}

resource "libvirt_domain" "agent" {
  count  = var.agent_count
  name   = format("rke2-agent-%02d", count.index + 1)
  memory = var.agent_ram
  vcpu   = var.agent_vcpus

  disk {
    volume_id = libvirt_volume.fcos_agent[count.index].id
  }

  network_interface {
    network_id = libvirt_network.default.id
  }

  cloudinit = file("${path.module}/rke2-agent-${format("%02d", count.index + 1)}.ign")
}

