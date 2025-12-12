#!/bin/bash

# ==========================================
# Production Server Init Script (v2.1 Final)
# Target: Ubuntu 24.04 / 22.04 LTS
# User: prod
# Stack: Nginx (Host) + Docker + NVM
# ==========================================

# --- 1. CONFIGURATION ---
NEW_USER="prod"
TIMEZONE="Asia/Bangkok"
SSH_PORT=2864  # ⭐ Custom SSH Port (จำเลขนี้ไว้นะครับ)

echo "🚀 Starting Production Server Provisioning..."

# --- 2. SYSTEM UPDATE ---
echo "📦 Updating system packages..."
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
    # Passwordless sudo for convenience
    echo "$NEW_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-prod-user
fi

# --- 4. SSH KEY SETUP ---
echo "🔑 Setting up SSH keys..."
mkdir -p /home/$NEW_USER/.ssh
chmod 700 /home/$NEW_USER/.ssh

if [ -f /root/.ssh/authorized_keys ]; then
    cp /root/.ssh/authorized_keys /home/$NEW_USER/.ssh/authorized_keys
    chmod 600 /home/$NEW_USER/.ssh/authorized_keys
    chown -R $NEW_USER:$NEW_USER /home/$NEW_USER/.ssh
    echo "✅ SSH Keys copied from root."
else
    echo "⚠️ WARNING: No SSH keys found. You must setup password login manually later."
fi

# --- 5. SECURITY HARDENING ---
echo "🛡️ Configuring Firewall (UFW)..."
ufw allow $SSH_PORT/tcp
ufw allow 'Nginx Full'
ufw --force enable

echo "🔒 Hardening SSH..."
mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/99-prod-hardening.conf <<EOF
Port $SSH_PORT
PermitRootLogin no
PasswordAuthentication no
ChallengeResponseAuthentication no
UsePAM yes
EOF
systemctl restart ssh

# --- 6. INSTALL DOCKER ---
echo "🐳 Installing Docker..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
    usermod -aG docker $NEW_USER
fi

# --- 7. INSTALL NODE.JS TOOLING (NVM) ---
echo "🟢 Installing NVM & Node for $NEW_USER..."
sudo -u $NEW_USER bash <<EOF
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
export NVM_DIR="/home/$NEW_USER/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && \. "\$NVM_DIR/nvm.sh"
nvm install --lts
nvm use --lts
npm install -g yarn pm2
EOF

# --- 8. DIRECTORY STRUCTURE ---
echo "📂 Setting up /var/www base structure..."
mkdir -p /var/www/html
chown -R $NEW_USER:www-data /var/www
chmod -R 775 /var/www
# Set SGID bit: New files inherit group www-data
chmod g+s /var/www

# --- 9. NGINX OPTIMIZATION ---
echo "⚡ Tuning Nginx..."
cat > /etc/nginx/conf.d/optimization.conf <<EOF
client_max_body_size 64M;
keepalive_timeout 65;
gzip on;
gzip_types text/plain text/css application/json application/javascript text/xml;
EOF

# Proxy Snippet
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

# --- 10. SMART HELPER SCRIPT ---
echo "🛠️ Creating smart helper script 'create_site'..."
mkdir -p /home/$NEW_USER/scripts
cat > /home/$NEW_USER/scripts/create_site.sh <<'EOF'
#!/bin/bash

# Interactive Site Creator
echo "-------------------------------------"
echo "🌐 WitMind Site Creator"
echo "-------------------------------------"

read -p "Enter Domain Name (e.g., app.witmind.ai): " DOMAIN
if [ -z "$DOMAIN" ]; then echo "❌ Domain is required."; exit 1; fi

echo ""
echo "Choose Site Type:"
echo "  1) Reverse Proxy (For Docker/Node/Python apps)"
echo "  2) Static HTML (For landing pages, React build)"
read -p "Select [1-2]: " TYPE

CONFIG="/etc/nginx/sites-available/$DOMAIN"

if [ "$TYPE" == "1" ]; then
    # --- TYPE 1: PROXY MODE ---
    read -p "Enter Local Port (e.g., 8000): " PORT
    if [ -z "$PORT" ]; then echo "❌ Port is required."; exit 1; fi

    echo "⚙️ Creating Proxy Config for $DOMAIN -> localhost:$PORT"
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

elif [ "$TYPE" == "2" ]; then
    # --- TYPE 2: STATIC MODE ---
    WEB_ROOT="/var/www/$DOMAIN"
    echo "⚙️ Creating Static Config for $DOMAIN -> $WEB_ROOT"
    
    # Create directory & placeholder
    sudo mkdir -p $WEB_ROOT
    sudo bash -c "echo '<h1>Hello $DOMAIN</h1>' > $WEB_ROOT/index.html"
    
    # Fix Permissions (Ensures 'prod' user can upload files here)
    sudo chown -R $USER:www-data $WEB_ROOT
    sudo chmod -R 775 $WEB_ROOT

    sudo bash -c "cat > $CONFIG" <<EOC
server {
    listen 80;
    server_name $DOMAIN;
    root $WEB_ROOT;
    index index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
EOC
    echo "📂 Web folder created at: $WEB_ROOT"
    echo "🚀 Upload your files using: scp -P $SSH_PORT -r ./dist/* $USER@YOUR_IP:$WEB_ROOT/"

else
    echo "❌ Invalid selection."
    exit 1
fi

# Enable Site
if [ -f "$CONFIG" ]; then
    sudo ln -sfn $CONFIG /etc/nginx/sites-enabled/
    sudo nginx -t
    if [ $? -eq 0 ]; then
        sudo systemctl reload nginx
        echo "✅ Site $DOMAIN is LIVE!"
        echo "🔒 To enable SSL, run: sudo certbot --nginx -d $DOMAIN"
    else
        echo "❌ Nginx config failed. Rolling back..."
        sudo rm /etc/nginx/sites-enabled/$DOMAIN
    fi
fi
EOF

chmod +x /home/$NEW_USER/scripts/create_site.sh
chown $NEW_USER:$NEW_USER /home/$NEW_USER/scripts/create_site.sh

# --- 11. CLEANUP ---
systemctl restart nginx
echo "✅ Server Provisioned Successfully!"
echo "----------------------------------------------------"
echo "⚠️  IMPORTANT: SSH Port changed to $SSH_PORT"
echo "👉 Login: ssh -p $SSH_PORT $NEW_USER@$(curl -s ifconfig.me)"
echo "----------------------------------------------------"