#!/bin/bash

# Port Manager - List and kill processes using specific ports
# Usage: ./portkill.sh [port_number] or ./portkill.sh

# Colors for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to display usage
show_usage() {
    echo -e "${BLUE}Usage:${NC}"
    echo "  $0                    - Interactive mode: list all ports and select"
    echo "  $0 [port_number]      - Direct mode: manage specific port"
    echo "  $0 -h, --help         - Show this help message"
    echo ""
    echo -e "${BLUE}Examples:${NC}"
    echo "  $0                    - Show all listening ports"
    echo "  $0 8080               - Show processes using port 8080"
    echo "  $0 3000               - Show processes using port 3000"
}

# Function to check if port is valid
is_valid_port() {
    local port=$1
    if [[ $port =~ ^[0-9]+$ ]] && [ $port -ge 1 ] && [ $port -le 65535 ]; then
        return 0
    else
        return 1
    fi
}

# Function to list all listening ports
list_all_ports() {
    echo -e "${BLUE}=== All Listening Ports ===${NC}"
    echo -e "${YELLOW}Port\tPID\tProcess\t\tProtocol\tAddress${NC}"
    echo "------------------------------------------------------------"
    
    # Use netstat or ss depending on availability
    if command -v ss &> /dev/null; then
        ss -tlnp | grep LISTEN | while IFS= read -r line; do
            port=$(echo "$line" | awk '{print $4}' | sed 's/.*://')
            pid=$(echo "$line" | awk '{print $6}' | grep -o 'pid=[0-9]*' | cut -d'=' -f2)
            address=$(echo "$line" | awk '{print $4}')
            protocol=$(echo "$line" | awk '{print $1}')
            
            if [ -n "$pid" ]; then
                process=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
                printf "%-8s%-8s%-16s%-12s%s\n" "$port" "$pid" "$process" "$protocol" "$address"
            fi
        done
    elif command -v netstat &> /dev/null; then
        netstat -tlnp 2>/dev/null | grep LISTEN | while IFS= read -r line; do
            port=$(echo "$line" | awk '{print $4}' | sed 's/.*://')
            pid_process=$(echo "$line" | awk '{print $7}')
            address=$(echo "$line" | awk '{print $4}')
            protocol=$(echo "$line" | awk '{print $1}')
            
            if [ "$pid_process" != "-" ] && [ -n "$pid_process" ]; then
                pid=$(echo "$pid_process" | cut -d'/' -f1)
                process=$(echo "$pid_process" | cut -d'/' -f2)
                printf "%-8s%-8s%-16s%-12s%s\n" "$port" "$pid" "$process" "$protocol" "$address"
            fi
        done
    else
        echo -e "${RED}Error: Neither 'ss' nor 'netstat' command found.${NC}"
        return 1
    fi
}

# Function to find processes using a specific port
find_port_processes() {
    local port=$1
    echo -e "${BLUE}=== Processes using port $port ===${NC}"
    
    local found=false
    
    # Check with lsof first (most reliable)
    if command -v lsof &> /dev/null; then
        local lsof_output=$(lsof -i :$port 2>/dev/null)
        if [ -n "$lsof_output" ]; then
            echo "$lsof_output"
            found=true
        fi
    fi
    
    # Fallback to netstat/ss
    if [ "$found" = false ]; then
        if command -v ss &> /dev/null; then
            local ss_output=$(ss -tlnp | grep ":$port ")
            if [ -n "$ss_output" ]; then
                echo -e "${YELLOW}PID\tProcess\t\tProtocol\tAddress${NC}"
                echo "$ss_output" | while IFS= read -r line; do
                    pid=$(echo "$line" | awk '{print $6}' | grep -o 'pid=[0-9]*' | cut -d'=' -f2)
                    address=$(echo "$line" | awk '{print $4}')
                    protocol=$(echo "$line" | awk '{print $1}')
                    
                    if [ -n "$pid" ]; then
                        process=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
                        printf "%-8s%-16s%-12s%s\n" "$pid" "$process" "$protocol" "$address"
                        found=true
                    fi
                done
            fi
        elif command -v netstat &> /dev/null; then
            local netstat_output=$(netstat -tlnp 2>/dev/null | grep ":$port ")
            if [ -n "$netstat_output" ]; then
                echo -e "${YELLOW}PID\tProcess\t\tProtocol\tAddress${NC}"
                echo "$netstat_output" | while IFS= read -r line; do
                    pid_process=$(echo "$line" | awk '{print $7}')
                    address=$(echo "$line" | awk '{print $4}')
                    protocol=$(echo "$line" | awk '{print $1}')
                    
                    if [ "$pid_process" != "-" ] && [ -n "$pid_process" ]; then
                        pid=$(echo "$pid_process" | cut -d'/' -f1)
                        process=$(echo "$pid_process" | cut -d'/' -f2)
                        printf "%-8s%-16s%-12s%s\n" "$pid" "$process" "$protocol" "$address"
                        found=true
                    fi
                done
            fi
        fi
    fi
    
    if [ "$found" = false ]; then
        echo -e "${YELLOW}No processes found using port $port${NC}"
        return 1
    fi
    
    return 0
}

# Function to get PIDs for a specific port
get_port_pids() {
    local port=$1
    local pids=()
    
    if command -v lsof &> /dev/null; then
        while IFS= read -r pid; do
            [ -n "$pid" ] && pids+=("$pid")
        done < <(lsof -t -i :$port 2>/dev/null)
    else
        # Fallback method
        if command -v ss &> /dev/null; then
            while IFS= read -r line; do
                local pid=$(echo "$line" | awk '{print $6}' | grep -o 'pid=[0-9]*' | cut -d'=' -f2)
                [ -n "$pid" ] && pids+=("$pid")
            done < <(ss -tlnp | grep ":$port ")
        elif command -v netstat &> /dev/null; then
            while IFS= read -r line; do
                local pid_process=$(echo "$line" | awk '{print $7}')
                if [ "$pid_process" != "-" ] && [ -n "$pid_process" ]; then
                    local pid=$(echo "$pid_process" | cut -d'/' -f1)
                    [ -n "$pid" ] && pids+=("$pid")
                fi
            done < <(netstat -tlnp 2>/dev/null | grep ":$port ")
        fi
    fi
    
    printf '%s\n' "${pids[@]}"
}

# Function to kill processes
kill_processes() {
    local port=$1
    local pids=($(get_port_pids $port))
    
    if [ ${#pids[@]} -eq 0 ]; then
        echo -e "${YELLOW}No processes found to kill on port $port${NC}"
        return 1
    fi
    
    echo -e "${RED}Found ${#pids[@]} process(es) using port $port${NC}"
    
    # Show process details before killing
    for pid in "${pids[@]}"; do
        if ps -p "$pid" > /dev/null 2>&1; then
            local cmd=$(ps -p "$pid" -o cmd= 2>/dev/null)
            echo -e "${YELLOW}PID $pid: $cmd${NC}"
        fi
    done
    
    echo ""
    read -p "Do you want to kill these processes? (y/N): " confirm
    
    if [[ $confirm =~ ^[Yy]$ ]]; then
        local killed=0
        for pid in "${pids[@]}"; do
            if ps -p "$pid" > /dev/null 2>&1; then
                if kill "$pid" 2>/dev/null; then
                    echo -e "${GREEN}✓ Killed process $pid${NC}"
                    ((killed++))
                else
                    echo -e "${RED}✗ Failed to kill process $pid (try with sudo?)${NC}"
                fi
            else
                echo -e "${YELLOW}! Process $pid already terminated${NC}"
            fi
        done
        
        if [ $killed -gt 0 ]; then
            echo -e "${GREEN}Successfully killed $killed process(es)${NC}"
            
            # Wait a moment and check if port is still in use
            sleep 1
            if ! find_port_processes $port > /dev/null 2>&1; then
                echo -e "${GREEN}Port $port is now free${NC}"
            else
                echo -e "${YELLOW}Some processes might still be using port $port${NC}"
            fi
        fi
    else
        echo -e "${YELLOW}Operation cancelled${NC}"
    fi
}

# Interactive mode to select port
interactive_mode() {
    while true; do
        echo ""
        list_all_ports
        echo ""
        echo -e "${BLUE}Options:${NC}"
        echo "1. Enter port number to manage"
        echo "2. Refresh list"
        echo "3. Exit"
        echo ""
        read -p "Choose an option (1-3): " choice
        
        case $choice in
            1)
                read -p "Enter port number: " port
                if is_valid_port "$port"; then
                    if find_port_processes "$port"; then
                        echo ""
                        read -p "Do you want to kill the processes using port $port? (y/N): " kill_confirm
                        if [[ $kill_confirm =~ ^[Yy]$ ]]; then
                            kill_processes "$port"
                        fi
                    fi
                else
                    echo -e "${RED}Invalid port number: $port${NC}"
                fi
                ;;
            2)
                # Just continue the loop to refresh
                ;;
            3)
                echo -e "${GREEN}Goodbye!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option${NC}"
                ;;
        esac
    done
}

# Main script logic
main() {
    # Check for help flag
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        show_usage
        exit 0
    fi
    
    # Check if running as root for better process management
    if [ $EUID -eq 0 ]; then
        echo -e "${YELLOW}Running as root - you can kill any process${NC}"
    fi
    
    # If no arguments, run interactive mode
    if [ $# -eq 0 ]; then
        echo -e "${GREEN}=== Port Manager - Interactive Mode ===${NC}"
        interactive_mode
    else
        # Direct mode with specific port
        local port=$1
        
        if ! is_valid_port "$port"; then
            echo -e "${RED}Error: Invalid port number '$port'${NC}"
            echo -e "${BLUE}Port must be a number between 1 and 65535${NC}"
            exit 1
        fi
        
        echo -e "${GREEN}=== Port Manager - Port $port ===${NC}"
        
        if find_port_processes "$port"; then
            echo ""
            kill_processes "$port"
        fi
    fi
}

# Run the main function with all arguments
main "$@"
