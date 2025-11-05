# Automated Docker Deployment Script

HNG DevOps Internship - Stage 1 Task

## Overview

This script automates the complete deployment of a Dockerized Node.js application to a remote Ubuntu server with Nginx reverse proxy.

## Features

- ✅ Automated repository cloning with GitHub PAT authentication
- ✅ SSH connection testing and validation
- ✅ Remote server setup (Docker, Docker Compose, Nginx)
- ✅ File transfer via rsync
- ✅ Docker image building and container deployment
- ✅ Nginx reverse proxy configuration
- ✅ Health checks and validation
- ✅ Comprehensive logging with timestamps
- ✅ Error handling and rollback
- ✅ Idempotent operations (safe to run multiple times)
- ✅ Cleanup functionality

## Prerequisites

### Local Machine
- Linux/Mac/WSL
- Git installed
- SSH client
- rsync

### Remote Server
- Ubuntu 20.04+ (tested on Ubuntu 22.04)
- Root or sudo access
- SSH access configured
- Public IP address

## Usage

### Deploy Application
bash
chmod +x deploy.sh
./deploy.sh


Follow the prompts to enter:
- GitHub repository URL
- GitHub Personal Access Token
- Branch name (default: main)
- SSH username
- Server IP address
- SSH key path (default: ~/.ssh/devops-key.pem)
- Application port (default: 3000)

### Cleanup Deployment

Remove all deployed resources:
bash
./deploy.sh --cleanup


## What It Does

1. *Repository Operations*: Clones or updates your Git repository
2. *SSH Connection*: Tests connection to remote server
3. *Server Setup*: Installs Docker, Docker Compose, and Nginx
4. *File Transfer*: Copies application files to server
5. *Docker Deployment*: Builds image and runs container
6. *Nginx Configuration*: Sets up reverse proxy on port 80
7. *Validation*: Tests endpoints and verifies deployment

## Configuration

The script uses the following default values:
- Default branch: main
- Default SSH key: ~/.ssh/devops-key.pem
- Default app port: 3000
- External port: 80 (HTTP)

## Logging

All operations are logged to timestamped files:

deploy_YYYYMMDD_HHMMSS.log


## Error Handling

- Validates all user inputs
- Checks SSH connectivity before deployment
- Verifies Dockerfile exists
- Confirms services are running
- Provides detailed error messages with line numbers

## Idempotency

The script can be safely run multiple times:
- Updates existing repository instead of re-cloning
- Checks if software is installed before installing
- Stops old containers before starting new ones
- Overwrites configurations safely

## Testing

After deployment, test your application:
bash
# Main endpoint
curl http://YOUR_SERVER_IP

# Health check
curl http://YOUR_SERVER_IP/health


Or open in browser:
- http://YOUR_SERVER_IP
- http://YOUR_SERVER_IP/health

## Troubleshooting

### SSH Connection Failed
bash
# Check SSH key permissions
chmod 400 ~/.ssh/devops-key.pem

# Test manual connection
ssh -i ~/.ssh/devops-key.pem ubuntu@YOUR_SERVER_IP


### Docker Permission Denied
bash
# Add user to docker group on remote server
ssh -i ~/.ssh/devops-key.pem ubuntu@YOUR_SERVER_IP
sudo usermod -aG docker ubuntu
exit

# Reconnect
ssh -i ~/.ssh/devops-key.pem ubuntu@YOUR_SERVER_IP
exit

# Run script again


### Port Already in Use
The script automatically stops old containers. If issues persist:
bash
ssh -i ~/.ssh/devops-key.pem ubuntu@YOUR_SERVER_IP
sudo docker ps
sudo docker stop app-container
sudo docker rm app-container


## Architecture

┌─────────────┐         ┌──────────────┐
│   Local     │  SSH    │    Remote    │
│   Machine   ├────────>│    Server    │
│             │  rsync  │  (Ubuntu)    │
└─────────────┘         └──────┬───────┘
                               │
                        ┌──────┴───────┐
                        │              │
                   ┌────▼────┐    ┌────▼────┐
                   │  Nginx  │    │ Docker  │
                   │  (Port  │    │Container│
                   │   80)   │    │ (Port   │
                   │         │───>│  3000)  │
                   └─────────┘    └─────────┘


## Security Notes

- Never commit your GitHub PAT to version control
- Use SSH keys instead of passwords
- Limit SSH access with security groups/firewall
- Consider using secrets management for production

## Author

Nweke Henry Chukwudi

## License

MIT

