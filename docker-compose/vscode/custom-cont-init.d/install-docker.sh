#!/bin/sh
# Install Docker CLI and fix socket permissions for the abc user.

# Make docker socket accessible
chmod 666 /var/run/docker.sock

# Install Docker CLI
apt-get update -qq && apt-get install -yqq --no-install-recommends \
  ca-certificates curl gnupg >/dev/null
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
apt-get update -qq && apt-get install -yqq --no-install-recommends \
  docker-ce-cli docker-compose-plugin >/dev/null
echo "Docker CLI installed: $(docker --version)"
