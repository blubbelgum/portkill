# Port Manager

A simple bash script to list and kill processes using specific ports.

## Installation

```bash
# Download the script
curl -O https://raw.githubusercontent.com/blubbelgum/portkill/main/portkill.sh

# Make it executable
chmod +x portkill.sh
```

## Usage

### Interactive Mode
```bash
./portkill.sh
```
Shows all listening ports and lets you select which one to manage.

### Direct Mode
```bash
./portkill.sh 8080
```
Directly manage processes using port 8080.

### Help
```bash
./portkill.sh --help
```

## Examples

Kill process on port 3000:
```bash
./portkill.sh 3000
```

List all ports and select interactively:
```bash
./portkill.sh
```

## Requirements

- Linux/macOS
- One of: `lsof`, `ss`, or `netstat`
- `ps` command

## Features

- Lists all listening ports with process details
- Safe process killing with confirmation
- Color-coded output
- Works with multiple network tools
- Input validation

## Output Example

```
=== Processes using port 8080 ===
COMMAND  PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
node     1234 user   20u  IPv4  12345      0t0  TCP *:8080 (LISTEN)

Do you want to kill the processes using port 8080? (y/N):
```

## License

MIT
