# 🚀 Production Server Init

Automated shell script to provision a secure, production-ready Ubuntu server with Nginx (Host) and Docker (Apps).

Designed for **Ubuntu 24.04 LTS** & **22.04 LTS**.

## ✨ Features

* **User Management:** Creates a `prod` user with sudo access (NOPASSWD) and SSH key login.
* **Security Hardening:**
    * UFW Firewall configured (SSH, HTTP, HTTPS).
    * Fail2Ban installed.
    * **Root login disabled.**
    * **Password authentication disabled** (Keys only).
* **Hybrid Stack:**
    * **Nginx (Host):** Optimized config, Gzip enabled, Modular proxy snippets.
    * **Docker (Apps):** Latest Docker Engine & Compose v2 installed.
    * **Node.js (Tooling):** NVM installed for `prod` user.
* **Helper Tools:** Includes `create_site.sh` to setup new reverse proxies in seconds.

## 🛠 Usage Guide

### 1. Prerequisites
* A fresh Ubuntu VPS/Droplet.
* **Important:** You must add your SSH Public Key to the server (Root) *before* running this script. The script copies root's keys to the new `prod` user.

### 2. Installation
SSH into your server as **root** and run:

```bash
# 1. Install Git & Go to /opt
apt update && apt install -y git
cd /opt

# 2. Clone this repo (Replace with your repo URL)
git clone [https://github.com/6amdev/production-server-init.git](https://github.com/YOUR_USERNAME/production-server-init.git)
cd production-server-init

# 3. Run the setup
chmod +x setup.sh
./setup.sh