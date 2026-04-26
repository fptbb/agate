#!/usr/bin/bash

set ${SET_X:+-x} -eou pipefail

trap '[[ $BASH_COMMAND != echo* ]] && [[ $BASH_COMMAND != log* ]] && echo "+ $BASH_COMMAND"' DEBUG

log() {
  echo "=== $* ==="
}

mkdir -p /etc/dnscrypt-proxy
mkdir -p /etc/systemd/resolved.conf.d

cat << 'EOF' > /etc/dnscrypt-proxy/dnscrypt-proxy.toml
server_names = ['odoh-cloudflare', 'odoh-snowstorm', 'odoh-crypto-sx', 'cs-brazil', 'cs-fl', 'dnscry.pt-valdivia-ipv4', 'dnscry.pt-lima02-ipv4']

# uses standard port to avoid selinux constraints
listen_addresses = ['127.0.0.1:53']
require_dnssec = true

odoh_servers = true
dnscrypt_servers = true
doh_servers = false
lb_strategy = 'fastest'

# provides bootstrap resolvers for initial list download
fallback_resolvers = ['9.9.9.9:53', '1.1.1.1:53']
ignore_system_dns = true

[anonymized_dns]
routes = [
  # explicitly matches server names to avoid protocol mismatch
  { server_name = 'odoh-cloudflare', via = ['odohrelay-crypto-sx', 'odohrelay-numa'] },
  { server_name = 'odoh-crypto-sx', via = ['odohrelay-crypto-sx', 'odohrelay-numa'] },
  { server_name = 'odoh-snowstorm', via = ['odohrelay-crypto-sx', 'odohrelay-numa'] },
  { server_name = '*', via = ['anon-cs-brazil', 'anon-cs-fl', 'anon-cs-brazil6', 'anon-cs-fl6'] }
]

[sources]

  [sources.'public-resolvers']
  urls = ['https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/public-resolvers.md', 'https://download.dnscrypt.info/resolvers-list/v3/public-resolvers.md', 'https://cdn.jsdelivr.net/gh/DNSCrypt/dnscrypt-resolvers@master/v3/public-resolvers.md']
  minisign_key = 'RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3'
  cache_file = 'public-resolvers.md'

  [sources.'relays']
  urls = ['https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/relays.md', 'https://download.dnscrypt.info/resolvers-list/v3/relays.md', 'https://cdn.jsdelivr.net/gh/DNSCrypt/dnscrypt-resolvers@master/v3/relays.md']
  minisign_key = 'RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3'
  cache_file = 'relays.md'

  [sources.'odoh-servers']
  urls = ['https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/odoh-servers.md', 'https://download.dnscrypt.info/resolvers-list/v3/odoh-servers.md', 'https://cdn.jsdelivr.net/gh/DNSCrypt/dnscrypt-resolvers@master/v3/odoh-servers.md']
  minisign_key = 'RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3'
  cache_file = 'odoh-servers.md'

  [sources.'odoh-relays']
  urls = ['https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/odoh-relays.md', 'https://download.dnscrypt.info/resolvers-list/v3/odoh-relays.md', 'https://cdn.jsdelivr.net/gh/DNSCrypt/dnscrypt-resolvers@master/v3/odoh-relays.md']
  minisign_key = 'RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3'
  cache_file = 'odoh-relays.md'
EOF

cat << 'EOF' > /etc/systemd/resolved.conf.d/dnscrypt.conf
[Resolve]
DNS=127.0.0.1:53

# forces domain routing to proxy
Domains=~.
EOF