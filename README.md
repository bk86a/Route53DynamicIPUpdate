# Route53DynamicIPUpdate

Dynamic DNS automation tool for AWS Route 53. Monitors public IP changes and automatically updates DNS A records for configured domains. Features robust error handling, email notifications, logging, and prevents unnecessary updates.

## Features

- ✅ Automatic public IP detection
- ✅ Smart DNS record updates (only when IP changes)
- ✅ Email notifications on updates
- ✅ Comprehensive logging
- ✅ JSON-based configuration
- ✅ Error handling and validation
- ✅ Supports multiple domains/zones

## Prerequisites

- AWS CLI installed and configured with Route 53 permissions
- `jq` for JSON parsing
- `msmtp` for email notifications (optional)
- `curl` for IP detection

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

## Installation

1. Clone this repository:
```bash
git clone https://github.com/bk86a/Route53DynamicIPUpdate.git
cd Route53DynamicIPUpdate
```

2. Make the script executable:
```bash
chmod +x update.sh
```

3. Configure your domains in `hosts.json`

## Configuration

### hosts.json

Edit `hosts.json` to include your domains and Route 53 zone information:

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

### Email Configuration

To receive email notifications, configure `msmtp`:

1. Install msmtp: `sudo apt install msmtp`
2. Configure `/etc/msmtprc` or `~/.msmtprc`
3. Update the `EMAIL` variable in `update.sh`

## Usage

### Manual Execution

Run the script manually:
```bash
./update.sh
```

### Automated Execution (Cron)

For automatic updates, add to your crontab:
```bash
# Check every 5 minutes
*/5 * * * * /path/to/route53/update.sh

# Check every hour
0 * * * * /path/to/route53/update.sh
```

## How It Works

1. **IP Detection**: Fetches current public IP from `checkip.amazonaws.com`
2. **Change Detection**: Compares with cached IP and Route 53 records
3. **Validation**: Validates JSON configuration and AWS connectivity
4. **Update Process**: Updates only records that don't match current IP
5. **Notification**: Sends email summary of changes (if configured)
6. **Logging**: Records all activities with timestamps

## Files and Directories

- `update.sh` - Main update script
- `hosts.json` - Domain configuration
- `/tmp/current_ip.txt` - Cached IP address
- `/var/log/route53_update.log` - Activity log
- `/tmp/change-batch.json` - Temporary AWS API payload

## Logging

All activities are logged to `/var/log/route53_update.log` with timestamps:

```
2023-12-07 10:30:15 - IP unchanged (203.0.113.42). Checking Route 53 for mismatches...
2023-12-07 10:30:16 - OK: example.com already 203.0.113.42
2023-12-07 10:30:17 - Updated A subdomain.example.com: 203.0.113.1 -> 203.0.113.42 (zone Z1234567890ABC)
```

## Error Handling

The script includes comprehensive error handling:

- **Network Issues**: Graceful handling of IP detection failures
- **AWS API Errors**: Proper error reporting for Route 53 operations
- **JSON Validation**: Validates configuration file before processing
- **Permission Issues**: Clear error messages for AWS credential problems

## Security Considerations

- No credentials stored in the script
- Uses AWS CLI credential chain (IAM roles, profiles, etc.)
- Minimal required AWS permissions
- Input validation and sanitization
- Secure temporary file handling

## Troubleshooting

### Common Issues

1. **"Could not determine public IP"**
   - Check internet connectivity
   - Verify `curl` is installed

2. **"Invalid JSON in hosts.json"**
   - Validate JSON syntax with `jq . hosts.json`
   - Check for trailing commas or syntax errors

3. **AWS Permission Errors**
   - Verify AWS CLI configuration: `aws sts get-caller-identity`
   - Check Route 53 permissions
   - Ensure correct zone IDs

4. **Email Not Working**
   - Check `msmtp` configuration
   - Verify email address in script
   - Test with `echo "test" | msmtp your@email.com`

### Debug Mode

For verbose output, modify the script to add debug logging:
```bash
set -x  # Add after the shebang line
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This project is open source. Feel free to use, modify, and distribute.

## Support

For issues and questions:
- Check the troubleshooting section
- Review log files in `/var/log/route53_update.log`
- Open an issue on GitHub

---

**Perfect for**: Home labs, small offices, development environments, or any setup requiring reliable dynamic DNS updates with AWS Route 53.