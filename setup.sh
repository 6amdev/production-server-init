#!/bin/bash

# ==========================================
# Production Server Init Script
# Target: Ubuntu 24.04 / 22.04 LTS
# User: prod
# Stack: Nginx (Host) + Docker + NVM
# ==========================================

# --- 1. CONFIGURATION ---
NEW_USER="prod"
TIMEZONE="Asia/Bangkok"

echo "🚀 Starting Production Server Provisioning..."

# --- 2. SYSTEM UPDATE ---
echo "📦 Updating system packages..."
# Prevent interactive pop-ups during install
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get upgrade -y
apt-get install -y curl git unzip htop ufw fail2ban certbot python3-certbot-nginx build-essential

# Set Timezone
timedatectl set-timezone $TIMEZONE

# --- 3. CREATE USER 'prod' ---
echo "👤 Creating user: $NEW_USER..."
if id "$NEW_USER" &>/dev/null; then
    echo "User $NEW_USER already exists."
else
    useradd -m -s /bin/bash $NEW_USER
    usermod -aG sudo $NEW_USER
    # Setup passwordless sudo for convenience (Prod user can run sudo without password)
    echo "$NEW_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-prod-user
fi

# --- 4. SSH KEY SETUP ---
echo "🔑 Setting up SSH keys..."
mkdir -p /home/$NEW_USER/.ssh
chmod 700 /home/$NEW_USER/.ssh

# Copy root's authorized_keys to prod (CRITICAL STEP)
if [ -f /root/.ssh/authorized_keys ]; then
    cp /root/.ssh/authorized_keys /home/$NEW_USER/.ssh/authorized_keys
    chmod 600 /home/$NEW_USER/.ssh/authorized_keys
    chown -R $NEW_USER:$NEW_USER /home/$NEW_USER/.ssh
    echo "✅ SSH Keys copied from root. You will be able to login as $NEW_USER."
else
    echo "⚠️ WARNING: No SSH keys found in root. You must setup password login manually later or add keys now."
fi

# --- 5. SECURITY HARDENING ---
echo "🛡️ Configuring Firewall (UFW)..."
ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw --force enable

echo "🔒 Hardening SSH..."
# Create custom config (Works on 22.04 and 24.04)
mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/99-prod-hardening.conf <<EOF
PermitRootLogin no
PasswordAuthentication no
ChallengeResponseAuthentication no
UsePAM yes
EOF

# Restart SSH service
systemctl restart ssh

# --- 6. INSTALL DOCKER ---
echo "🐳 Installing Docker..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
    # Add prod to docker group (Run docker without sudo)
    usermod -aG docker $NEW_USER
fi

# --- 7. INSTALL NODE.JS TOOLING (NVM) ---
echo "🟢 Installing NVM & Node (Client Tools) for $NEW_USER..."
# Run installation as the 'prod' user to keep /home/prod clean
sudo -u $NEW_USER bash <<EOF
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
export NVM_DIR="/home/$NEW_USER/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && \. "\$NVM_DIR/nvm.sh"
# Install LTS Node.js
nvm install --lts
nvm use --lts
# Install global tools
npm install -g yarn pm2
EOF

# --- 8. DIRECTORY STRUCTURE ---
echo "📂 Setting up /var/www structure..."
mkdir -p /var/www/html
mkdir -p /var/www/witmind

# Permission Strategy: Owner=prod, Group=www-data
chown -R $NEW_USER:www-data /var/www
chmod -R 775 /var/www
# Set SGID bit (New files created inside will inherit group www-data)
chmod g+s /var/www

# --- 9. NGINX OPTIMIZATION ---
echo "⚡ Tuning Nginx..."
cat > /etc/nginx/conf.d/optimization.conf <<EOF
client_max_body_size 64M;
keepalive_timeout 65;
gzip on;
gzip_types text/plain text/css application/json application/javascript text/xml application/xml+rss text/javascript;
EOF

# Create Proxy Snippet for Reusability
mkdir -p /etc/nginx/snippets
cat > /etc/nginx/snippets/proxy_params.conf <<EOF
proxy_http_version 1.1;
proxy_set_header Upgrade \$http_upgrade;
proxy_set_header Connection "upgrade";
proxy_set_header Host \$host;
proxy_set_header X-Real-IP \$remote_addr;
proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto \$scheme;
proxy_cache_bypass \$http_upgrade;
EOF

# --- 10. HELPER SCRIPT (Create Site) ---
echo "🛠️ Creating helper script 'create_site'..."
mkdir -p /home/$NEW_USER/scripts
cat > /home/$NEW_USER/scripts/create_site.sh <<'EOF'
#!/bin/bash
DOMAIN=$1
PORT=$2

if [ -z "$DOMAIN" ] || [ -z "$PORT" ]; then
  echo "Usage: ./create_site.sh <domain> <port>"
  echo "Example: ./create_site.sh api.witmind.ai 8000"
  exit 1
fi

CONFIG="/etc/nginx/sites-available/$DOMAIN"

echo "Creating Nginx config for $DOMAIN -> localhost:$PORT"

sudo bash -c "cat > $CONFIG" <<EOC
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://localhost:$PORT;
        include /etc/nginx/snippets/proxy_params.conf;
    }
}
EOC

sudo ln -s $CONFIG /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

echo "✅ Site created! Now run: sudo certbot --nginx -d $DOMAIN"
EOF

chmod +x /home/$NEW_USER/scripts/create_site.sh
chown $NEW_USER:$NEW_USER /home/$NEW_USER/scripts/create_site.sh

# --- 11. CLEANUP ---
systemctl restart nginx
echo "✅ Server Provisioned Successfully!"
echo "----------------------------------------------------"
echo "Root login is now DISABLED."
echo "Please login as: ssh $NEW_USER@$(curl -s ifconfig.me)"
echo "----------------------------------------------------"