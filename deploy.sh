#!/bin/bash

#============================================
# DevOps Deployment Automation Script
# HNG DevOps Internship - Stage 1
# Automated Docker deployment with Nginx reverse proxy
#============================================

set -e
set -o pipefail

#============================================
# CLEANUP FUNCTION
#============================================

cleanup_deployment() {
    echo "Starting cleanup process..."
    
    if [ -z "$SSH_USER" ] || [ -z "$SERVER_IP" ] || [ -z "$SSH_KEY" ]; then
        echo "Please provide SSH credentials for cleanup:"
        read -p "SSH Username: " SSH_USER
        read -p "Server IP: " SERVER_IP
        read -p "SSH Key Path [~/.ssh/devops-key.pem]: " SSH_KEY
        SSH_KEY=${SSH_KEY:-~/.ssh/devops-key.pem}
        SSH_KEY="${SSH_KEY/#\~/$HOME}"
    fi
    
    echo "Cleaning up deployment on $SSH_USER@$SERVER_IP..."
    
    ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" bash <<'CLEANUPEOF'
echo "Stopping and removing containers..."
sudo docker stop app-container 2>/dev/null || true
sudo docker rm app-container 2>/dev/null || true

echo "Removing Docker image..."
sudo docker rmi devops-app:latest 2>/dev/null || true

echo "Removing application files..."
rm -rf ~/app

echo "Removing Nginx configuration..."
sudo rm -f /etc/nginx/sites-enabled/devops-app
sudo rm -f /etc/nginx/sites-available/devops-app
sudo systemctl reload nginx

echo "Cleanup completed!"
CLEANUPEOF
    
    echo "✓ All resources removed successfully"
    exit 0
}

# Check for cleanup flag
if [ "$1" = "--cleanup" ]; then
    cleanup_deployment
fi

#============================================
# CONFIGURATION
#============================================

LOG_FILE="deploy_$(date +%Y%m%d_%H%M%S).log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

#============================================
# HELPER FUNCTIONS
#============================================

log() {
    local message="$1"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo -e "${BLUE}[${timestamp}]${NC} ${message}" | tee -a "$LOG_FILE"
}

success() {
    local message="$1"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo -e "${GREEN}[${timestamp}] ✓ ${message}${NC}" | tee -a "$LOG_FILE"
}

error_exit() {
    local message="$1"
    local exit_code="${2:-1}"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo -e "${RED}[${timestamp}] ✗ ERROR: ${message}${NC}" | tee -a "$LOG_FILE"
    echo -e "${RED}Check log file: ${LOG_FILE}${NC}"
    exit "$exit_code"
}

warn() {
    local message="$1"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo -e "${YELLOW}[${timestamp}] ⚠ ${message}${NC}" | tee -a "$LOG_FILE"
}

trap 'error_exit "Script failed at line $LINENO" 1' ERR

#============================================
# START SCRIPT
#============================================

log "==================================================="
log "     DevOps Deployment Script Started"
log "==================================================="
log "Log file: $LOG_FILE"
log ""

success "Logging system initialized successfully"

#============================================
# COLLECT USER INPUT
#============================================

log "Collecting deployment parameters..."
log ""

while true; do
    echo -ne "${BLUE}Enter Git Repository URL: ${NC}"
    read GIT_REPO
    if [[ "$GIT_REPO" =~ ^https://github\.com/.+/.+ ]]; then
        [[ "$GIT_REPO" != *.git ]] && GIT_REPO="${GIT_REPO}.git"
        success "Repository URL validated: $GIT_REPO"
        break
    else
        warn "Invalid GitHub URL format"
    fi
done

while true; do
    echo -ne "${BLUE}Enter GitHub Personal Access Token: ${NC}"
    read -s GIT_PAT
    echo ""
    if [[ ${#GIT_PAT} -ge 40 ]]; then
        success "GitHub token received"
        break
    else
        warn "Token seems too short"
    fi
done

echo -ne "${BLUE}Enter branch name [main]: ${NC}"
read GIT_BRANCH
GIT_BRANCH=${GIT_BRANCH:-main}
log "Using branch: $GIT_BRANCH"

while true; do
    echo -ne "${BLUE}Enter SSH Username: ${NC}"
    read SSH_USER
    if [[ -n "$SSH_USER" ]]; then
        success "SSH username: $SSH_USER"
        break
    else
        warn "Username cannot be empty"
    fi
done

while true; do
    echo -ne "${BLUE}Enter Server IP Address: ${NC}"
    read SERVER_IP
    if [[ "$SERVER_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        success "Server IP: $SERVER_IP"
        break
    else
        warn "Invalid IP format"
    fi
done

echo -ne "${BLUE}Enter SSH Key Path [~/.ssh/devops-key.pem]: ${NC}"
read SSH_KEY
SSH_KEY=${SSH_KEY:-~/.ssh/devops-key.pem}
SSH_KEY="${SSH_KEY/#\~/$HOME}"

if [[ -f "$SSH_KEY" ]]; then
    success "SSH key found: $SSH_KEY"
    KEY_PERMS=$(stat -c %a "$SSH_KEY" 2>/dev/null || stat -f %A "$SSH_KEY" 2>/dev/null)
    if [[ "$KEY_PERMS" != "400" ]] && [[ "$KEY_PERMS" != "600" ]]; then
        chmod 400 "$SSH_KEY"
        success "SSH key permissions fixed"
    fi
else
    error_exit "SSH key not found at: $SSH_KEY" 2
fi

while true; do
    echo -ne "${BLUE}Enter Application Port [3000]: ${NC}"
    read APP_PORT
    APP_PORT=${APP_PORT:-3000}
    if [[ "$APP_PORT" =~ ^[0-9]+$ ]] && [ "$APP_PORT" -ge 1 ] && [ "$APP_PORT" -le 65535 ]; then
        success "Application port: $APP_PORT"
        break
    else
        warn "Invalid port number"
    fi
done

log ""
log "==================================================="
log "Configuration Summary:"
log "==================================================="
log "Repository: $GIT_REPO"
log "Branch: $GIT_BRANCH"
log "Server: $SSH_USER@$SERVER_IP"
log "SSH Key: $SSH_KEY"
log "App Port: $APP_PORT"
log "==================================================="
log ""

echo -ne "${YELLOW}Proceed with deployment? (yes/no): ${NC}"
read CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
    error_exit "Deployment cancelled by user" 0
fi

log "Starting deployment process..."

#============================================
# CLONE/UPDATE REPOSITORY
#============================================

log "==================================================="
log "STEP 1: Repository Operations"
log "==================================================="

REPO_NAME=$(basename "$GIT_REPO" .git)
log "Repository name: $REPO_NAME"

REPO_WITH_TOKEN=$(echo "$GIT_REPO" | sed "s|https://|https://${GIT_PAT}@|")

if [ -d "$REPO_NAME" ]; then
    log "Repository directory exists, updating..."
    cd "$REPO_NAME" || error_exit "Cannot access repository directory" 2
    
    log "Fetching latest changes from remote..."
    git fetch origin || error_exit "Git fetch failed" 3
    
    log "Switching to branch: $GIT_BRANCH"
    git checkout "$GIT_BRANCH" || error_exit "Branch checkout failed" 3
    
    log "Pulling latest changes..."
    git pull origin "$GIT_BRANCH" || error_exit "Git pull failed" 3
    
    success "Repository updated successfully"
else
    log "Cloning repository for the first time..."
    git clone -b "$GIT_BRANCH" "$REPO_WITH_TOKEN" "$REPO_NAME" || error_exit "Git clone failed" 3
    cd "$REPO_NAME" || error_exit "Cannot access cloned directory" 2
    success "Repository cloned successfully"
fi

CURRENT_DIR=$(pwd)
log "Current directory: $CURRENT_DIR"

log "Checking for Dockerfile..."
if [[ -f "Dockerfile" ]]; then
    success "Dockerfile found"
elif [[ -f "docker-compose.yml" ]]; then
    success "docker-compose.yml found"
else
    error_exit "No Dockerfile or docker-compose.yml found in repository" 4
fi

CURRENT_BRANCH=$(git branch --show-current)
CURRENT_COMMIT=$(git rev-parse --short HEAD)
log "Current branch: $CURRENT_BRANCH"
log "Current commit: $CURRENT_COMMIT"

success "Repository operations completed"
log ""

#============================================
# TEST SSH CONNECTION
#============================================

log "==================================================="
log "STEP 2: Testing SSH Connection"
log "==================================================="

log "Connecting to $SSH_USER@$SERVER_IP..."

if ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$SSH_USER@$SERVER_IP" "echo 'SSH OK'" > /dev/null 2>&1; then
    success "SSH connection established"
else
    error_exit "SSH connection failed" 5
fi

log "Gathering server information..."
SERVER_HOSTNAME=$(ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" "hostname")
SERVER_OS=$(ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" "cat /etc/os-release | grep PRETTY_NAME | cut -d'\"' -f2")

log "Server hostname: $SERVER_HOSTNAME"
log "Server OS: $SERVER_OS"

success "SSH connection test completed"
log ""

#============================================
# SETUP REMOTE SERVER
#============================================

log "==================================================="
log "STEP 3: Setting Up Remote Server"
log "==================================================="

log "Installing Docker, Docker Compose, and Nginx..."

ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" 'bash -s' <<'REMOTESCRIPT'
set -e

echo "[REMOTE] Updating packages..."
sudo apt-get update -y

echo "[REMOTE] Checking Docker..."
if ! command -v docker &> /dev/null; then
    echo "[REMOTE] Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
else
    echo "[REMOTE] Docker already installed"
fi

echo "[REMOTE] Checking Docker Compose..."
if ! command -v docker-compose &> /dev/null; then
    echo "[REMOTE] Installing Docker Compose..."
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
else
    echo "[REMOTE] Docker Compose already installed"
fi

echo "[REMOTE] Checking Nginx..."
if ! command -v nginx &> /dev/null; then
    echo "[REMOTE] Installing Nginx..."
    sudo apt-get install -y nginx
else
    echo "[REMOTE] Nginx already installed"
fi

echo "[REMOTE] Starting services..."
sudo systemctl enable docker
sudo systemctl start docker
sudo systemctl enable nginx
sudo systemctl start nginx

docker --version
docker-compose --version
nginx -v
REMOTESCRIPT

success "Remote server setup completed"

DOCKER_STATUS=$(ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" "sudo systemctl is-active docker")
if [ "$DOCKER_STATUS" = "active" ]; then
    success "Docker service is running"
fi

NGINX_STATUS=$(ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" "sudo systemctl is-active nginx")
if [ "$NGINX_STATUS" = "active" ]; then
    success "Nginx service is running"
fi

log ""

#============================================
# TRANSFER FILES
#============================================

log "==================================================="
log "STEP 4: Transferring Files"
log "==================================================="

ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" "mkdir -p ~/app"

log "Transferring files..."
rsync -avz --progress \
    -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no" \
    --exclude='.git' \
    --exclude='node_modules' \
    ./ "$SSH_USER@$SERVER_IP:~/app/" || error_exit "Transfer failed" 7

success "Files transferred"
log ""

#============================================
# DEPLOY DOCKER
#============================================

log "==================================================="
log "STEP 5: Deploying Docker Application"
log "==================================================="

ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" bash <<DEPLOYEOF
set -e
cd ~/app
echo "[REMOTE] Stopping old containers..."
sudo docker stop app-container 2>/dev/null || true
sudo docker rm app-container 2>/dev/null || true
echo "[REMOTE] Building image..."
sudo docker build -t devops-app:latest .
echo "[REMOTE] Running container..."
sudo docker run -d --name app-container -p $APP_PORT:3000 --restart unless-stopped devops-app:latest
sleep 5
sudo docker ps | grep app-container
DEPLOYEOF

success "Docker application deployed"
log ""

#============================================
# CONFIGURE NGINX
#============================================

log "==================================================="
log "STEP 6: Configuring Nginx"
log "==================================================="

ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" bash <<NGINXEOF
sudo tee /etc/nginx/sites-available/devops-app > /dev/null <<'CONF'
server {
    listen 80;
    server_name _;
    location / {
        proxy_pass http://localhost:$APP_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
    location /health {
        proxy_pass http://localhost:$APP_PORT/health;
        proxy_set_header Host \$host;
    }
}
CONF
sudo sed -i "s/\\\$APP_PORT/$APP_PORT/g" /etc/nginx/sites-available/devops-app
sudo ln -sf /etc/nginx/sites-available/devops-app /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx
NGINXEOF

success "Nginx configured"
log ""

#============================================
# FINAL VALIDATION
#============================================

log "==================================================="
log "STEP 7: Final Validation"
log "==================================================="

sleep 2
RESPONSE=$(ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" "curl -s -o /dev/null -w '%{http_code}' http://localhost")

if [ "$RESPONSE" = "200" ]; then
    success "Application is responding (HTTP $RESPONSE)"
fi

HEALTH=$(ssh -i "$SSH_KEY" "$SSH_USER@$SERVER_IP" "curl -s http://localhost/health")
log "Health check: $HEALTH"

log ""
log "==================================================="
log "DEPLOYMENT COMPLETED SUCCESSFULLY!"
log "==================================================="
log ""
success "Application is now accessible at:"
log "  → http://$SERVER_IP"
log "  → http://$SERVER_IP/health"
log ""
log "Deployment Summary:"
log "  - Repository: $GIT_REPO"
log "  - Branch: $GIT_BRANCH"
log "  - Commit: $CURRENT_COMMIT"
log "  - Server: $SSH_USER@$SERVER_IP"
log "  - Container: app-container"
log "  - Port: $APP_PORT → 80"
log ""
log "To remove all deployed resources, run:"
log "  ./deploy.sh --cleanup"
log ""
log "Log: $LOG_FILE"
log "==================================================="

