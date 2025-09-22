#!/bin/bash
set -euo pipefail

# Route53 Dynamic IP Update - Installation Script
# This script helps set up the Route53 Dynamic IP Update tool

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🚀 Route53 Dynamic IP Update - Installation Script"
echo "================================================="

# Check if running as root for system-wide installation
if [[ $EUID -eq 0 ]]; then
    echo "⚠️  Running as root. This will install system-wide."
    INSTALL_DIR="/opt/route53-updater"
    LOG_DIR="/var/log"
    SYSTEMD_INSTALL=true
else
    echo "📁 Running as user. This will install to your home directory."
    INSTALL_DIR="$HOME/.local/bin/route53-updater"
    LOG_DIR="$HOME/.local/var/log"
    SYSTEMD_INSTALL=false
fi

echo "📍 Installation directory: $INSTALL_DIR"

# Check dependencies
echo
echo "🔍 Checking dependencies..."
MISSING_DEPS=()

for cmd in curl jq aws; do
    if ! command -v "$cmd" &> /dev/null; then
        MISSING_DEPS+=("$cmd")
    else
        echo "✅ $cmd found"
    fi
done

if [[ ${#MISSING_DEPS[@]} -gt 0 ]]; then
    echo
    echo "❌ Missing dependencies: ${MISSING_DEPS[*]}"
    echo
    echo "Please install missing dependencies:"
    echo "Ubuntu/Debian: sudo apt update && sudo apt install curl jq awscli"
    echo "CentOS/RHEL:   sudo yum install curl jq awscli"
    echo "macOS:         brew install curl jq awscli"
    exit 1
fi

# Check AWS CLI configuration
echo
echo "🔑 Checking AWS CLI configuration..."
if aws sts get-caller-identity &>/dev/null; then
    echo "✅ AWS CLI configured"
    aws sts get-caller-identity --query 'Account' --output text | sed 's/^/   Account: /'
else
    echo "⚠️  AWS CLI not configured"
    echo "   Please run: aws configure"
    echo "   Or set up IAM roles/environment variables"
fi

# Create installation directory
echo
echo "📂 Creating installation directory..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$LOG_DIR"

# Copy files
echo "📋 Copying files..."
cp "$SCRIPT_DIR/update.sh" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/hosts.json.example" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/config.env.example" "$INSTALL_DIR/"

# Make script executable
chmod +x "$INSTALL_DIR/update.sh"

# Create default configuration if it doesn't exist
if [[ ! -f "$INSTALL_DIR/config.env" ]]; then
    echo "⚙️  Creating default configuration..."
    cp "$INSTALL_DIR/config.env.example" "$INSTALL_DIR/config.env"

    # Update log path in config
    sed -i "s|LOG_FILE=\"/var/log/route53_update.log\"|LOG_FILE=\"$LOG_DIR/route53_update.log\"|g" "$INSTALL_DIR/config.env"

    echo "📝 Please edit $INSTALL_DIR/config.env to configure your settings"
fi

# Create hosts.json if it doesn't exist
if [[ ! -f "$INSTALL_DIR/hosts.json" ]]; then
    echo "🏠 Creating hosts configuration template..."
    cp "$INSTALL_DIR/hosts.json.example" "$INSTALL_DIR/hosts.json"
    echo "📝 Please edit $INSTALL_DIR/hosts.json to configure your domains"
fi

# Create systemd service (if running as root)
if [[ "$SYSTEMD_INSTALL" == "true" ]]; then
    echo
    echo "⚙️  Setting up systemd service..."

    cat > /etc/systemd/system/route53-updater.service <<EOF
[Unit]
Description=Route53 Dynamic IP Update Service
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/update.sh
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    cat > /etc/systemd/system/route53-updater.timer <<EOF
[Unit]
Description=Route53 Dynamic IP Update Timer
Requires=route53-updater.service

[Timer]
OnCalendar=*:0/5
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    echo "✅ Systemd service created"
    echo "   Enable with: sudo systemctl enable --now route53-updater.timer"
    echo "   Check status: sudo systemctl status route53-updater.timer"
fi

# Create cron entry suggestion
echo
echo "⏰ Cron setup suggestion:"
if [[ "$SYSTEMD_INSTALL" == "true" ]]; then
    echo "   Use systemd timer (recommended): sudo systemctl enable --now route53-updater.timer"
    echo "   Or add to root crontab:"
    echo "   */5 * * * * $INSTALL_DIR/update.sh >/dev/null 2>&1"
else
    echo "   Add to your crontab (crontab -e):"
    echo "   */5 * * * * $INSTALL_DIR/update.sh >/dev/null 2>&1"
fi

# Create symlink for easy access
if [[ "$SYSTEMD_INSTALL" == "true" ]]; then
    ln -sf "$INSTALL_DIR/update.sh" /usr/local/bin/route53-update
    echo "🔗 Created symlink: /usr/local/bin/route53-update"
else
    mkdir -p "$HOME/.local/bin"
    ln -sf "$INSTALL_DIR/update.sh" "$HOME/.local/bin/route53-update"
    echo "🔗 Created symlink: $HOME/.local/bin/route53-update"
    echo "   Make sure $HOME/.local/bin is in your PATH"
fi

echo
echo "✅ Installation completed!"
echo
echo "📝 Next steps:"
echo "1. Edit $INSTALL_DIR/config.env to configure your settings"
echo "2. Edit $INSTALL_DIR/hosts.json to add your domains and zones"
echo "3. Test the script: $INSTALL_DIR/update.sh"
echo "4. Set up automated execution (cron or systemd timer)"
echo
echo "📚 Documentation: https://github.com/bk86a/Route53DynamicIPUpdate"
echo "🐛 Issues: https://github.com/bk86a/Route53DynamicIPUpdate/issues"