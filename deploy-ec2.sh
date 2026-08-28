#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./deploy-ec2.sh <ec2-public-ip> <ssh-user> <ssh-key-path>
# Example:
#   ./deploy-ec2.sh 54.123.45.67 ec2-user ~/.ssh/my-key.pem
# Example (Ubuntu):
#   ./deploy-ec2.sh 54.123.45.67 ubuntu ~/.ssh/my-key.pem

HOST="${1:-}"
USER="${2:-ec2-user}"
KEY_PATH="${3:-~/.ssh/id_rsa}"
KEY_PATH="${KEY_PATH/#\~/$HOME}"
WAR_NAME="demo-0.0.1-SNAPSHOT.war"
WAR_PATH="backend/target/${WAR_NAME}"

if [[ -z "$HOST" ]]; then
  echo "Usage: $0 <ec2-public-ip> [ssh-user] [ssh-key-path]"
  echo "Example: $0 54.123.45.67 ec2-user ~/.ssh/my-key.pem"
  exit 1
fi

if [[ ! -f "$WAR_PATH" ]]; then
  echo "WAR not found at $WAR_PATH"
  echo "Building frontend + backend first..."

  cd frontend
  npm ci --no-audit --no-fund
  npm run build
  cd ..

  mkdir -p backend/src/main/resources/static
  cp -R frontend/dist/* backend/src/main/resources/static/

  cd backend
  mvn clean package -DskipTests
  cd ..
fi

if [[ ! -f "$WAR_PATH" ]]; then
  echo "Build failed: $WAR_PATH still missing."
  exit 1
fi

echo "[1/4] Building app artifacts..."
# build step is already ensured above
ls -l "$WAR_PATH"

echo "[2/4] Copying WAR to EC2..."
scp -i "$KEY_PATH" "$WAR_PATH" "${USER}@${HOST}:/tmp/${WAR_NAME}"

echo "[3/4] Preparing EC2 system and deploying WAR..."
ssh -i "$KEY_PATH" "${USER}@${HOST}" bash -s <<'REMOTE'
set -euo pipefail

if [ -f /etc/os-release ]; then
  . /etc/os-release
fi

if [[ "${ID:-}" == "ubuntu" || "${ID:-}" == "debian" ]]; then
  sudo apt-get update -y
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-17-jdk tomcat10
  TOMCAT_WEBAPPS="/var/lib/tomcat10/webapps"
  TOMCAT_SERVICE="tomcat10"
elif [[ "${ID:-}" == "amzn" || "${ID:-}" == "al2023" ]]; then
  sudo dnf install -y java-17-amazon-corretto tomcat10
  TOMCAT_WEBAPPS="/var/lib/tomcat/webapps"
  TOMCAT_SERVICE="tomcat10"
else
  echo "Unsupported OS. Please run on Ubuntu/Debian or Amazon Linux 2023."
  exit 1
fi

sudo mkdir -p "$TOMCAT_WEBAPPS"
sudo cp /tmp/demo-0.0.1-SNAPSHOT.war "$TOMCAT_WEBAPPS/ROOT.war"
sudo chown tomcat:tomcat "$TOMCAT_WEBAPPS/ROOT.war" || true
sudo systemctl daemon-reload || true
sudo systemctl enable "$TOMCAT_SERVICE" || true
sudo systemctl restart "$TOMCAT_SERVICE"
sleep 5

# Basic firewall for Linux
if command -v ufw >/dev/null 2>&1; then
  sudo ufw allow 8080/tcp || true
  sudo ufw allow 80/tcp || true
  sudo ufw --force enable || true
fi

if command -v firewall-cmd >/dev/null 2>&1; then
  sudo firewall-cmd --permanent --add-port=8080/tcp || true
  sudo firewall-cmd --reload || true
fi

echo "Tomcat deployed. Checking app..."
curl -fsS http://localhost:8080/ >/dev/null || true
curl -fsS http://localhost:8080/api/hello || true
REMOTE

echo "[4/4] Deployment complete."
echo "Open: http://${HOST}:8080/"
