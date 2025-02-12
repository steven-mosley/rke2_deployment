# tfvars

domain              = "astronet.local"
control_plane_count = 1
agent_count         = 2
control_plane_ram   = 4096
control_plane_vcpus = 2
agent_ram           = 2048
agent_vcpus         = 1
fcos_image_path     = "./fedora-coreos.qcow2"
fcos_disk_size      = 10737418240
control_plane_url   = "https://rke2-cp-01.astronet.local:9345"

