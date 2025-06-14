# Port Kill

A dead simple bash script for managing processes using network ports on Linux/macOS systems.

## Features

- **Multiple port formats**: Single ports, ranges, and comma-separated lists
- **Enhanced process information**: CPU usage, memory usage, and full command details
- **Flexible filtering**: Include/exclude specific processes or users
- **Watch mode**: Real-time monitoring of port usage
- **Safe operations**: Dry-run mode and confirmation prompts
- **JSON output**: Machine-readable format for automation
- **Saved port lists**: Store and reuse common port configurations
- **Interactive mode**: User-friendly interface for port management

## Installation

```bash
# Download the script
curl -O https://raw.githubusercontent.com/blubbelgum/portkill/main/portkill.sh

# Make it executable
chmod +x portkill.sh

# Optional: Install system-wide
sudo cp portkill.sh /usr/local/bin/portkill
```

## Usage

### Basic Usage

```bash
# Interactive mode
./portkill.sh

# Single port
./portkill.sh 8080

# Multiple ports
./portkill.sh 8080,3000,5432

# Port range
./portkill.sh 8000-8010

# Show help
./portkill.sh --help
```

### Advanced Options

```bash
# Dry run (show what would be killed)
./portkill.sh --dry-run 8080

# Force kill (SIGKILL instead of SIGTERM)
./portkill.sh --force 3000

# Auto-confirm without prompts
./portkill.sh --yes 8080

# JSON output for automation
./portkill.sh --json 8080

# Watch mode (real-time monitoring)
./portkill.sh --watch

# Quiet mode (minimal output)
./portkill.sh --quiet 8080
```

### Filtering Options

```bash
# Only show specific processes
./portkill.sh --only node,python 8080

# Exclude specific processes
./portkill.sh --exclude docker,nginx

# Exclude specific users
./portkill.sh --exclude-users root,daemon

# Confirmation timeout (auto-confirm after N seconds)
./portkill.sh --timeout 5 8080
```

### Saved Port Lists

```bash
# Save a port list
./portkill.sh --save-list webdev 3000,8080,8443

# Load a saved port list
./portkill.sh --load-list webdev

# List saved port lists
./portkill.sh --list-saved

# Show common port shortcuts
./portkill.sh --common
```

## Examples

### Web Development
```bash
# Kill all web development processes
./portkill.sh 3000,8080,8443

# Monitor development ports in real-time
./portkill.sh --watch 3000-3010
```

### Database Management
```bash
# Check database ports
./portkill.sh --dry-run 3306,5432,27017

# Kill only MySQL processes
./portkill.sh --only mysql 3306
```

### System Administration
```bash
# Force kill stubborn processes
./portkill.sh --force --yes 8080

# Generate JSON report
./portkill.sh --json --quiet > port_report.json

# Exclude system processes
./portkill.sh --exclude-users root,daemon 80,443
```

## Interactive Mode

The interactive mode provides a menu-driven interface:

1. **Port Management**: Enter ports in any supported format
2. **Saved Lists**: Load and manage saved port configurations
3. **Filter Toggle**: Enable/disable filters and options
4. **Watch Mode**: Real-time monitoring
5. **Refresh**: Update the port list

## Output Formats

### Standard Output
```
=== Port 8080 ===
PID: 1234 | User: user | Process: node | CPU: 2.5% | Mem: 1.2%
Command: node server.js
```

### JSON Output
```json
{
  "results": [
    {
      "port": 8080,
      "processes": [
        {
          "pid": 1234,
          "user": "user",
          "process": "node",
          "cpu_percent": "2.5",
          "memory_percent": "1.2",
          "command": "node server.js"
        }
      ]
    }
  ]
}
```

## Requirements

- **Operating System**: Linux or macOS
- **Network Tools**: One of `lsof`, `ss`, or `netstat`
- **Process Tools**: `ps` command
- **Shell**: Bash 4.0+

## Configuration

The script stores saved port lists in `~/.portkill_config`. This file contains name-value pairs of saved port configurations.

## Safety Features

- **Confirmation prompts** for destructive operations
- **Dry-run mode** to preview actions
- **Process validation** before killing
- **Graceful termination** (SIGTERM) by default
- **User filtering** to prevent accidental system process kills

## Exit Codes

- `0`: Success
- `1`: Error (invalid arguments, no processes found, etc.)

## License

MIT a.k.a use it for free
