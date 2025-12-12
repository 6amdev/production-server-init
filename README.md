# 🚀 Production Server Init

Automated shell script to provision a secure Ubuntu server with Nginx (Host), Docker (Apps), and NVM.


🛠 Installation
Run as root on a fresh Ubuntu server:

# 1. Clone Repo
git clone [https://github.com/6amdev/production-server-init.git](https://github.com/YOUR_USERNAME/production-server-init.git)
cd production-server-init

# 2. Run Setup
chmod +x setup.sh
./setup.sh

Note: Root login will be disabled. Login as prod on port 2864 after setup.

📖 How to Create Sites
Login as prod and run: ./scripts/create_site.sh

Scenario A: Docker App (e.g., Node.js/Python on Port 8000)
Run ./scripts/create_site.sh

Select Type 1 (Reverse Proxy)

Enter Domain (api.witmind.ai) and Port (8000)

Enable SSL: sudo certbot --nginx -d api.witmind.ai

Scenario B: Static Site (e.g., HTML/React)
Run ./scripts/create_site.sh

Select Type 2 (Static HTML)

Enter Domain (witmind.ai)

Upload files to: /var/www/witmind.ai/

Enable SSL: sudo certbot --nginx -d witmind.ai

⚡ Quick Commands
New Site: ./scripts/create_site.sh

Deploy Docker: docker compose up -d

Restart Nginx: sudo systemctl restart nginx