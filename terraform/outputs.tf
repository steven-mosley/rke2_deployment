# Provides output about the domain, tokens, etc.

output "control_plane_domains" {
  value = [for cp in module.control_plane : cp.domain_name]
}

output "agent_domains" {
  value = [for a in module.agent : a.domain_name]
}

output "rke2_token" {
  value = random_password.rke2_token.result
}

