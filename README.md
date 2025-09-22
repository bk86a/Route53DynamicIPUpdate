# Route53DynamicIPUpdate

Dynamic DNS automation tool for AWS Route 53. Monitors public IP changes and automatically updates DNS A records for configured domains. Features robust error handling, email notifications, logging, and prevents unnecessary updates.

## Features

- 🚀 **Automatic public IP detection** with multiple fallback services
- 🔄 **Smart DNS record updates** (only when IP changes or mismatches detected)
- 📧 **Email notifications** on updates (optional)
- 📊 **Comprehensive logging** with configurable levels
- ⚙️ **JSON-based configuration** with environment variable support
- 🛡️ **Enhanced error handling** with retry logic
- 🌐 **Multiple domains/zones** support
- 🔒 **Security-focused** with input validation and secure temp files
- 📦 **Easy installation** with automated installer
- 🧪 **Unit tests** included

## 🚀 Quick Start

## Installation

1. **Clone and install:**
```bash
git clone https://github.com/bk86a/Route53DynamicIPUpdate.git
cd Route53DynamicIPUpdate
sudo ./install.sh  # or ./install.sh for user installation
```

2. **Configure your domains:**
```bash
cp hosts.json.example hosts.json
nano hosts.json  # Add your domains and Route53 zone IDs
```

3. **Configure settings:**
```bash
cp config.env.example config.env
nano config.env  # Set your email and preferences
```

4. **Test the setup:**
```bash
./update.sh
```

### Manual Installation

1. **Clone this repository:**
```bash
git clone https://github.com/bk86a/Route53DynamicIPUpdate.git
cd Route53DynamicIPUpdate
```

2. **Make the script executable:**
```bash
chmod +x update.sh
```

3. **Configure your environment and domains (see Configuration section)**

## 📋 Prerequisites

- **AWS CLI** installed and configured with Route 53 permissions
- **jq** for JSON parsing
- **curl** for IP detection
- **msmtp** for email notifications (optional)

### Required AWS Permissions

Your AWS credentials need the following permissions:
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "route53:ListResourceRecordSets",
                "route53:ChangeResourceRecordSets"
            ],
            "Resource": "*"
        }
    ]
}
```

## Configuration

### Environment Configuration (`config.env`)

Copy `config.env.example` to `config.env` and customize:

```bash
# Email settings
EMAIL="your-email@example.com"
ENABLE_EMAIL_NOTIFICATIONS="true"

# File paths
HOSTS_JSON_FILE="./hosts.json"
LOG_FILE="/var/log/route53_update.log"

# IP detection with fallbacks
PRIMARY_IP_SERVICE="http://checkip.amazonaws.com"
FALLBACK_IP_SERVICES="https://ipinfo.io/ip https://api.ipify.org"

# Retry configuration
MAX_RETRIES="3"
RETRY_DELAY="5"

# Logging
LOG_LEVEL="INFO"  # DEBUG, INFO, WARN, ERROR
ENABLE_STRUCTURED_LOGGING="false"
```

### Hosts Configuration (`hosts.json`)

Copy `hosts.json.example` to `hosts.json` and add your domains:

```json
{
  "records": [
    {
      "name": "example.com",
      "zone_id": "Z1234567890ABC",
      "type": "A",
      "ttl": 300
    },
    {
      "name": "subdomain.example.com",
      "zone_id": "Z1234567890ABC",
      "type": "A",
      "ttl": 300
    }
  ]
}
```

**Fields:**
- `name`: The fully qualified domain name
- `zone_id`: Your Route 53 hosted zone ID
- `type`: Record type (currently only "A" records are supported)
- `ttl`: Time-to-live in seconds

## Usage

### Manual Execution

```bash
./update.sh
```

### Automated Execution

#### Using systemd (recommended for system-wide installation)

```bash
# Enable and start the timer (runs every 5 minutes)
sudo systemctl enable --now route53-updater.timer

# Check status
sudo systemctl status route53-updater.timer

# View logs
journalctl -u route53-updater.service
```

#### Using cron

```bash
# Edit crontab
crontab -e

# Add one of these lines:
# Check every 5 minutes
*/5 * * * * /path/to/route53/update.sh >/dev/null 2>&1

# Check every hour
0 * * * * /path/to/route53/update.sh >/dev/null 2>&1
```

## 🔧 How It Works

1. **IP Detection**: Tries primary service, falls back to alternatives if needed
2. **Validation**: Validates IP format and JSON configuration
3. **Change Detection**: Compares with cached IP and current Route 53 records
4. **Dependency Check**: Verifies all required tools are available
5. **Update Process**: Updates only records that don't match current IP
6. **Retry Logic**: Retries failed AWS API calls with exponential backoff
7. **Notification**: Sends email summary of changes (if configured)
8. **Logging**: Records all activities with configurable detail levels

## 📁 Files and Directories

- `update.sh` - Main update script
- `config.env` - Configuration file (create from example)
- `hosts.json` - Domain configuration (create from example)
- `install.sh` - Automated installation script
- `tests/` - Unit test suite
- `/tmp/route53_current_ip.txt` - Cached IP address (default location)
- `/var/log/route53_update.log` - Activity log (default location)

## 📊 Logging

All activities are logged with timestamps and configurable levels:

### Standard Logging
```
2024-09-22 10:30:15 - INFO: Current public IP: 203.0.113.42
2024-09-22 10:30:16 - INFO: example.com: Already correct (203.0.113.42)
2024-09-22 10:30:17 - INFO: Updated subdomain.example.com: 203.0.113.1 -> 203.0.113.42
```

### Structured Logging (JSON)
```json
{"timestamp":"2024-09-22 10:30:15","level":"INFO","message":"Current public IP: 203.0.113.42"}
{"timestamp":"2024-09-22 10:30:17","level":"INFO","message":"Updated subdomain.example.com: 203.0.113.1 -> 203.0.113.42"}
```

## 🛡️ Security Features

- **No hardcoded credentials** - Uses AWS CLI credential chain
- **Input validation** - All inputs are validated and sanitized
- **Secure temporary files** - Uses `mktemp` with proper permissions
- **Minimal AWS permissions** - Only requires Route 53 access
- **IP format validation** - Ensures valid IPv4 addresses
- **Safe error handling** - No sensitive data in error messages

## 🧪 Testing

Run the test suite:

```bash
# Run tests
./tests/test_basic.sh
```

## Troubleshooting

### Common Issues

1. **"Could not determine public IP"**
   - Check internet connectivity
   - Try manual IP detection: `curl -s http://checkip.amazonaws.com`
   - Configure fallback services in `config.env`

2. **"Invalid JSON in hosts.json"**
   - Validate JSON syntax: `jq . hosts.json`
   - Check for trailing commas or syntax errors

3. **AWS Permission Errors**
   - Verify AWS CLI: `aws sts get-caller-identity`
   - Check Route 53 permissions
   - Ensure correct zone IDs in `hosts.json`

4. **"Missing required dependencies"**
   - Install missing packages: `sudo apt install curl jq awscli`

### Debug Mode

Enable debug logging:
```bash
# In config.env
LOG_LEVEL="DEBUG"

# Or run directly
LOG_LEVEL=DEBUG ./update.sh
```

### Test Configuration

Validate your setup without making changes:
```bash
# Dry run mode (check config only)
aws route53 list-resource-record-sets --hosted-zone-id YOUR_ZONE_ID
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Run tests (`./tests/test_basic.sh`)
5. Commit your changes (`git commit -m 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 📞 Support

- 📖 **Documentation**: Check this README and inline script comments
- 🐛 **Issues**: [GitHub Issues](https://github.com/bk86a/Route53DynamicIPUpdate/issues)
- 💬 **Discussions**: [GitHub Discussions](https://github.com/bk86a/Route53DynamicIPUpdate/discussions)

## 📊 Changelog

See [CHANGELOG.md](CHANGELOG.md) for a detailed history of changes.

---

**Perfect for**: Home labs, small offices, development environments, or any setup requiring reliable dynamic DNS updates with AWS Route 53.

**⭐ If this project helps you, please consider giving it a star!**