#!/bin/sh
set -ef

# shellcheck disable=2269
vault_tls_dir=${vault_tls_dir}

# Atomic rename so the readers see either the old file or the new file,
# never a zero-byte file mid-write.
mv -f "\${vault_tls_dir}/server.key.new" "\${vault_tls_dir}/server.key"
mv -f "\${vault_tls_dir}/server.crt.new" "\${vault_tls_dir}/server.crt"

systemctl kill --signal=SIGHUP --kill-whom=main vault.service
