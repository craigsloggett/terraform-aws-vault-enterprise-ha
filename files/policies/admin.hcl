# Manage auth methods broadly across Vault
path "auth/*" {
  capabilities = ["create", "read", "update", "patch", "delete", "list", "sudo"]
}

# PKI Secret Engines
path "pki_*" {
  capabilities = ["create", "read", "update", "patch", "delete", "list", "sudo"]
}

# Create, update, and delete auth methods
path "sys/auth/*" {
  capabilities = ["create", "read", "update", "patch", "delete", "list", "sudo"]
}

# List auth methods
path "sys/auth" {
  capabilities = ["read"]
}

# Create and manage ACL policies
path "sys/policies/acl/*" {
  capabilities = ["create", "read", "update", "patch", "delete", "list", "sudo"]
}

# List ACL policies
path "sys/policies/acl" {
  capabilities = ["list"]
}

# Create and manage secrets engines broadly across Vault
path "sys/mounts/*" {
  capabilities = ["create", "read", "update", "patch", "delete", "list", "sudo"]
}

# List enabled secrets engines
path "sys/mounts" {
  capabilities = ["read", "list"]
}

# List, create, update, and delete key/value secrets
path "secret/*" {
  capabilities = ["create", "read", "update", "patch", "delete", "list", "sudo"]
}

# Manage transit secrets engine
path "transit/*" {
  capabilities = ["create", "read", "update", "patch", "delete", "list", "sudo"]
}

# Read health checks
path "sys/health" {
  capabilities = ["read", "sudo"]
}

# Identity engine
path "identity/*" {
  capabilities = ["create", "read", "update", "patch", "delete", "list"]
}

# Lease management
path "sys/leases/*" {
  capabilities = ["create", "read", "update", "patch", "delete", "list", "sudo"]
}

# Plugin catalog
path "sys/plugins/catalog/*" {
  capabilities = ["create", "read", "update", "patch", "delete", "list", "sudo"]
}

# Plugin backend reload
path "sys/plugins/reload/backend" {
  capabilities = ["create", "update"]
}
