# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2024-09-22

### Added
- Configuration file support (`config.env`)
- Environment variable support for all settings
- IP validation with proper format checking
- Multiple IP service fallback for redundancy
- Enhanced error handling and retry logic
- Structured logging option (JSON format)
- Configurable log levels (DEBUG, INFO, WARN, ERROR)
- AWS CLI profile and region support
- Dependency checking on startup
- Secure temporary file creation
- Better email notification handling
- Comprehensive input validation
- Support for custom AWS CLI profiles and regions

### Changed
- **BREAKING**: Removed hardcoded personal information
- **BREAKING**: Configuration now uses `config.env` file
- **BREAKING**: Hosts configuration moved to `hosts.json` (was hardcoded)
- Improved logging with timestamps and levels
- Better error messages and troubleshooting information
- Enhanced security with input sanitization
- More robust AWS API error handling

### Security
- Removed personal email addresses and domain names
- Added input validation for all user inputs
- Secure temporary file handling with proper permissions
- No credentials stored in the script

### Documentation
- Added comprehensive README with examples
- Created configuration templates
- Added troubleshooting guide
- Included security considerations

## [1.0.0] - 2024-09-21

### Added
- Initial release
- Basic Route53 A record updating
- IP change detection and caching
- Email notifications via msmtp
- JSON configuration support
- AWS Route53 integration
- Basic error handling and logging