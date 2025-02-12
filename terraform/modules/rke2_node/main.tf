# This module renders the Butane template, transpiles it to Ignition, and then provisions a VM with libvirt.

locals {
  # Render the Butane configuration from our template file.
  butane_config = templatefile("${path.module}/rke2-node-config.bu.tpl", {
    hostname = var.hostname
    role     = var.role
    token    = var.token
    server   = var.server
  })
}

# Write the rendered Butane config to a file.
resource "local_file" "node_butane" {
  filename = "${path.module}/${var.hostname}.bu"
  content  = local.butane_config
}

# Transpile the Butane configuration to an Ignition file using butane.
resource "null_resource" "transpile" {
  # Use a dummy trigger so that if the Butane file changes, we regenerate Ignition.
  triggers = {
    bu_content = local_file.node_butane.content
  }
  provisioner "local-exec" {
    command = "butane --pretty --strict < ${local_file.node_butane.filename} > ${path.module}/${var.hostname}.ign"
  }
}

# Provision a disk for the node using a Fedora CoreOS QCOW2 image.
resource "libvirt_volume" "fcos_disk" {
  name    = "${var.hostname}.qcow2"
  pool    = "default"
  source  = var.fcos_image_path
  format  = "qcow2"
  size    = var.disk_size
}

# Create a cloud-init ISO using the generated Ignition file.
resource "libvirt_cloudinit_disk" "ci" {
  name      = "${var.hostname}-cloudinit.iso"
  user_data = file("${path.module}/${var.hostname}.ign")
  depends_on = [null_resource.transpile]
}

# Create the VM (libvirt_domain) for this node.
resource "libvirt_domain" "node" {
  name   = var.hostname
  memory = var.memory
  vcpu   = var.vcpu

  disk {
    volume_id = libvirt_volume.fcos_disk.id
  }
  disk {
    volume_id = libvirt_cloudinit_disk.ci.id
  }

  network_interface {
    network_name   = "default"
    wait_for_lease = true
  }

  console {
    type        = "pty"
    target_port = "0"
  }
}

