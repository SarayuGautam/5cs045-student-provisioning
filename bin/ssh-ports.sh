#!/bin/bash
# Prints the ports sshd accepts connections on, comma-separated, for example "22".
# The port can be set in sshd's own settings or, on Ubuntu
# 24.04, in ssh.socket (systemd listens on the port and starts sshd for each connection), so both
# are read. fail2ban and the health check use this to watch the port students actually connect to.
{
  sshd -T 2>/dev/null | awk '$1 == "port" { print $2 }'
  systemctl show -p Listen --value ssh.socket 2>/dev/null | grep -oE ':[0-9]+ ' | tr -d ': '
} | awk 'NF && !seen[$0]++' | paste -sd, -
