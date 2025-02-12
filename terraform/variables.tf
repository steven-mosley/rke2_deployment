# Provides variables for the root module

variable "domain" {
  description = "The internal domain for the cluster."
  type        = string
  default     = "astronet.local"
}

variable "control_plane_count" {
  description = "Number of control plane nodes."
  type        = number
  default     = 1
}

variable "agent_count" {
  description = "Number of agent nodes."
  type        = number
  default     = 2
}

variable "control_plane_ram" {
  description = "RAM (in MiB) for control plane nodes."
  type        = number
  default     = 4096
}

variable "control_plane_vcpus" {
  description = "Number of vCPUs for control plane nodes."
  type        = number
  default     = 2
}

variable "agent_ram" {
  description = "RAM (in MiB) for agent nodes."
  type        = number
  default     = 2048
}

variable "agent_vcpus" {
  description = "Number of vCPUs for agent nodes."
  type        = number
  default     = 1
}

variable "fcos_image_path" {
  description = "Path to the Fedora CoreOS QCOW2 image on the local filesystem."
  type        = string
  default     = "fedora-coreos.qcow2"
}

variable "fcos_disk_size" {
  description = "Size (in bytes) for the provisioned disk (should be larger than the QCOW2 base image)."
  type        = number
  default     = 10737418240  # 10 GiB
}

variable "control_plane_url" {
  description = "The URL of the control plane (for agents to join)."
  type        = string
  default     = "https://rke2-cp-01.astronet.local:9345"
}

