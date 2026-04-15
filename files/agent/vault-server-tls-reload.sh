#!/bin/sh
set -ef

# Atomic rename so the readers see either the old file or the new file,
# never a zero-byte file mid-write.
mv -f /opt/vault/tls/server.key.new /opt/vault/tls/server.key
mv -f /opt/vault/tls/server.crt.new /opt/vault/tls/server.crt

systemctl kill --signal=SIGHUP --kill-whom=main vault.service
