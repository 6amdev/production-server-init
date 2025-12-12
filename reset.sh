#!/bin/bash

# ==========================================
# SERVER NUKE SCRIPT (RESET TO FRESH STATE)
# Warning: This will delete user 'prod' and all data!
# ==========================================

echo "⚠️  WARNING: This script will WIPE EVERYTHING configured by setup.sh"
echo "   - User 'prod' will be deleted"
echo "   - All Docker containers & data will be lost"
echo "   - Nginx & SSL certs will be deleted"
echo "   - SSH will be reset to Port 22"
echo ""
read -p "Are you sure? Type 'DESTROY' to confirm: " CONFIRM

if [ "$CONFIRM" != "DESTROY" ]; then
    echo "❌ Aborted."
    exit 1
fi

echo "🚀 Starting System Cleanup..."

# 1. STOP SERVICES
echo "🛑 Stopping services..."
systemctl stop nginx
systemctl stop docker
systemctl stop apache2 2>/dev/null

# 2. REMOVE PACKAGES
echo "🗑️ Removing packages..."
apt-get purge -y nginx nginx-common nginx-core certbot python3-certbot-nginx docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
apt-get autoremove -y

# 3. DELETE FILES & FOLDERS
echo "🔥 Deleting files..."
rm -rf /var/www/*
rm -rf /etc/nginx
rm -rf /etc/letsencrypt
rm -rf /var/lib/docker
rm -rf /etc/docker

# 4. DELETE USER 'PROD'
echo "👤 Deleting user 'prod'..."
if id "prod" &>/dev/null; then
    deluser --remove-home prod
    rm -f /etc/sudoers.d/90-prod-user
    echo "✅ User 'prod' deleted."
else
    echo "User 'prod' not found."
fi

# 5. RESET SSH & FIREWALL (Back to Default)
echo "🛡️ Resetting SSH & Firewall..."

# Remove custom SSH config
rm -f /etc/ssh/sshd_config.d/99-prod-hardening.conf

# Reset UFW
ufw --force reset
ufw allow 22/tcp  # Open default SSH
ufw --force enable

# Restart SSH to apply Port 22
systemctl restart ssh

echo "=========================================="
echo "✅ CLEANUP COMPLETE!"
echo "You can now re-run 'setup.sh' cleanly."
echo "👉 Please re-login as 'root' on PORT 22"
echo "=========================================="