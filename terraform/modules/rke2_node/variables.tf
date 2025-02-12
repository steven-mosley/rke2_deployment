# Variables used throughout the module

variable "hostname" {
  description = "The fully-qualified hostname for this node."
  type        = string
}

variable "role" {
  description = "The node role: either 'server' or 'agent'."
  type        = string
}

variable "token" {
  description = "The RKE2 token shared by all nodes."
  type        = string
}

variable "server" {
  description = "The control plane URL. For agents, this is used to join the cluster. For control plane nodes it can be empty or self-referential."
  type        = string
  default     = ""
}

variable "fcos_image_path" {
  description = "Path to the Fedora CoreOS QCOW2 image on the local filesystem."
  type        = string
}

variable "disk_size" {
  description = "Disk size in bytes for the provisioned disk."
  type        = number
}

variable "memory" {
  description = "RAM (in MiB) for the VM."
  type        = number
}

variable "vcpu" {
  description = "Number of vCPUs for the VM."
  type        = number
}

