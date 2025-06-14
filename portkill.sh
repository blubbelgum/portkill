#!/bin/bash

# Port Manager - List and kill processes using specific ports
# Usage: ./portkill.sh [options] [port_number|port_range|port_list]

VERSION="2.0"

# Colors for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Global options
FORCE_KILL=false
DRY_RUN=false
QUIET=false
WATCH_MODE=false
JSON_OUTPUT=false
EXCLUDE_USERS=()
ONLY_PROCESSES=()
EXCLUDE_PROCESSES=()
AUTO_CONFIRM=false
CONFIRMATION_TIMEOUT=0

# Config file for saved port lists
CONFIG_FILE="$HOME/.portkill_config"

# Function to display usage
show_usage() {
    echo -e "${BLUE}${BOLD}Port Kill v$VERSION${NC}"
    echo -e "${BLUE}Usage:${NC}"
    echo "  $0 [options] [port(s)]"
    echo ""
    echo -e "${BLUE}Port Formats:${NC}"
    echo "  $0 8080                    - Single port"
    echo "  $0 8080,3000,5432          - Multiple ports"
    echo "  $0 8000-8010               - Port range"
    echo "  $0                         - Interactive mode"
    echo ""
    echo -e "${BLUE}Options:${NC}"
    echo "  -f, --force                Force kill (SIGKILL)"
    echo "  -d, --dry-run              Show what would be killed"
    echo "  -q, --quiet                Minimal output"
    echo "  -w, --watch                Watch mode (auto-refresh)"
    echo "  -j, --json                 JSON output"
    echo "  -y, --yes                  Auto-confirm kills"
    echo "  -t, --timeout SECONDS      Confirmation timeout"
    echo "  --only PROCESSES           Only show specific processes (comma-separated)"
    echo "  --exclude PROCESSES        Exclude processes (comma-separated)"
    echo "  --exclude-users USERS      Exclude users (comma-separated)"
    echo "  --save-list NAME           Save port list to config"
    echo "  --load-list NAME           Load port list from config"
    echo "  --list-saved               Show saved port lists"
    echo "  --common                   Show common port shortcuts"
    echo "  -h, --help                 Show this help"
    echo ""
    echo -e "${BLUE}Examples:${NC}"
    echo "  $0 --dry-run 8080          - See what would be killed on port 8080"
    echo "  $0 --force 3000-3010       - Force kill all processes on ports 3000-3010"
    echo "  $0 --only node,python      - Only show Node.js and Python processes"
    echo "  $0 --exclude root          - Exclude root user processes"
    echo "  $0 --watch                 - Continuously monitor all ports"
}

# Function to show common ports
show_common_ports() {
    echo -e "${BLUE}${BOLD}Common Port Shortcuts:${NC}"
    echo -e "${YELLOW}Web Servers:${NC} 80,443,8080,8443,3000,5000"
    echo -e "${YELLOW}Databases:${NC} 3306,5432,27017,6379,5984"
    echo -e "${YELLOW}Development:${NC} 3000,3001,4200,8080,8000,9000"
    echo -e "${YELLOW}API Services:${NC} 8080,8443,9090,3000,5000"
    echo ""
    echo "Usage: $0 80,443,8080 (for web servers)"
}

# Function to parse port arguments
parse_ports() {
    local input="$1"
    local ports=()
    
    # Handle comma-separated ports
    if [[ $input == *","* ]]; then
        IFS=',' read -ra PORT_ARRAY <<< "$input"
        for port in "${PORT_ARRAY[@]}"; do
            port=$(echo "$port" | tr -d ' ')
            if [[ $port == *"-"* ]]; then
                # Handle range within comma-separated list
                local start=$(echo "$port" | cut -d'-' -f1)
                local end=$(echo "$port" | cut -d'-' -f2)
                for ((p=start; p<=end; p++)); do
                    if is_valid_port "$p"; then
                        ports+=("$p")
                    fi
                done
            else
                if is_valid_port "$port"; then
                    ports+=("$port")
                fi
            fi
        done
    # Handle port range
    elif [[ $input == *"-"* ]]; then
        local start=$(echo "$input" | cut -d'-' -f1)
        local end=$(echo "$input" | cut -d'-' -f2)
        for ((p=start; p<=end; p++)); do
            if is_valid_port "$p"; then
                ports+=("$p")
            fi
        done
    # Single port
    else
        if is_valid_port "$input"; then
            ports+=("$input")
        fi
    fi
    
    printf '%s\n' "${ports[@]}"
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

# Function to check if process should be included
should_include_process() {
    local pid=$1
    local process_name=$2
    local user=$3
    
    # Check excluded users
    for excluded_user in "${EXCLUDE_USERS[@]}"; do
        if [[ "$user" == "$excluded_user" ]]; then
            return 1
        fi
    done
    
    # Check excluded processes
    for excluded_proc in "${EXCLUDE_PROCESSES[@]}"; do
        if [[ "$process_name" == *"$excluded_proc"* ]]; then
            return 1
        fi
    done
    
    # Check only processes filter
    if [ ${#ONLY_PROCESSES[@]} -gt 0 ]; then
        local found=false
        for only_proc in "${ONLY_PROCESSES[@]}"; do
            if [[ "$process_name" == *"$only_proc"* ]]; then
                found=true
                break
            fi
        done
        if [ "$found" = false ]; then
            return 1
        fi
    fi
    
    return 0
}

# Function to get process info
get_process_info() {
    local pid=$1
    local user=$(ps -p "$pid" -o user= 2>/dev/null | tr -d ' ')
    local cmd=$(ps -p "$pid" -o comm= 2>/dev/null)
    local full_cmd=$(ps -p "$pid" -o args= 2>/dev/null)
    local cpu=$(ps -p "$pid" -o %cpu= 2>/dev/null | tr -d ' ')
    local mem=$(ps -p "$pid" -o %mem= 2>/dev/null | tr -d ' ')
    
    echo "$user,$cmd,$full_cmd,$cpu,$mem"
}

# Function to list all listening ports with enhanced info
list_all_ports() {
    if [ "$JSON_OUTPUT" = true ]; then
        list_ports_json
        return
    fi
    
    if [ "$QUIET" = false ]; then
        echo -e "${BLUE}${BOLD}=== All Listening Ports ===${NC}"
        echo -e "${YELLOW}Port\tPID\tUser\t\tProcess\t\tCPU%\tMem%\tCommand${NC}"
        echo "--------------------------------------------------------------------------------"
    fi
    
    local port_data=()
    
    # Use lsof for better reliability
    if command -v lsof &> /dev/null; then
        while IFS= read -r line; do
            if [[ $line == *"LISTEN"* ]]; then
                local pid=$(echo "$line" | awk '{print $2}')
                local port=$(echo "$line" | awk '{print $9}' | sed 's/.*://')
                
                if [[ $port =~ ^[0-9]+$ ]] && [ -n "$pid" ]; then
                    local proc_info=$(get_process_info "$pid")
                    local user=$(echo "$proc_info" | cut -d',' -f1)
                    local process=$(echo "$proc_info" | cut -d',' -f2)
                    local full_cmd=$(echo "$proc_info" | cut -d',' -f3)
                    local cpu=$(echo "$proc_info" | cut -d',' -f4)
                    local mem=$(echo "$proc_info" | cut -d',' -f5)
                    
                    if should_include_process "$pid" "$process" "$user"; then
                        if [ "$QUIET" = false ]; then
                            printf "%-8s%-8s%-12s%-16s%-8s%-8s%s\n" "$port" "$pid" "$user" "$process" "$cpu%" "$mem%" "$full_cmd"
                        fi
                        port_data+=("$port:$pid:$user:$process:$cpu:$mem:$full_cmd")
                    fi
                fi
            fi
        done < <(lsof -i -P -n 2>/dev/null)
    else
        # Fallback to ss/netstat
        if command -v ss &> /dev/null; then
            while IFS= read -r line; do
                local port=$(echo "$line" | awk '{print $4}' | sed 's/.*://')
                local pid=$(echo "$line" | awk '{print $6}' | grep -o 'pid=[0-9]*' | cut -d'=' -f2)
                
                if [ -n "$pid" ] && [[ $port =~ ^[0-9]+$ ]]; then
                    local proc_info=$(get_process_info "$pid")
                    local user=$(echo "$proc_info" | cut -d',' -f1)
                    local process=$(echo "$proc_info" | cut -d',' -f2)
                    local full_cmd=$(echo "$proc_info" | cut -d',' -f3)
                    local cpu=$(echo "$proc_info" | cut -d',' -f4)
                    local mem=$(echo "$proc_info" | cut -d',' -f5)
                    
                    if should_include_process "$pid" "$process" "$user"; then
                        if [ "$QUIET" = false ]; then
                            printf "%-8s%-8s%-12s%-16s%-8s%-8s%s\n" "$port" "$pid" "$user" "$process" "$cpu%" "$mem%" "$full_cmd"
                        fi
                        port_data+=("$port:$pid:$user:$process:$cpu:$mem:$full_cmd")
                    fi
                fi
            done < <(ss -tlnp | grep LISTEN)
        fi
    fi
    
    # Store for other functions to use
    printf '%s\n' "${port_data[@]}"
}

# Function to output ports in JSON format
list_ports_json() {
    echo "{"
    echo "  \"ports\": ["
    local first=true
    
    if command -v lsof &> /dev/null; then
        while IFS= read -r line; do
            if [[ $line == *"LISTEN"* ]]; then
                local pid=$(echo "$line" | awk '{print $2}')
                local port=$(echo "$line" | awk '{print $9}' | sed 's/.*://')
                
                if [[ $port =~ ^[0-9]+$ ]] && [ -n "$pid" ]; then
                    local proc_info=$(get_process_info "$pid")
                    local user=$(echo "$proc_info" | cut -d',' -f1)
                    local process=$(echo "$proc_info" | cut -d',' -f2)
                    local full_cmd=$(echo "$proc_info" | cut -d',' -f3)
                    local cpu=$(echo "$proc_info" | cut -d',' -f4)
                    local mem=$(echo "$proc_info" | cut -d',' -f5)
                    
                    if should_include_process "$pid" "$process" "$user"; then
                        if [ "$first" = false ]; then
                            echo ","
                        fi
                        echo "    {"
                        echo "      \"port\": $port,"
                        echo "      \"pid\": $pid,"
                        echo "      \"user\": \"$user\","
                        echo "      \"process\": \"$process\","
                        echo "      \"cpu_percent\": \"$cpu\","
                        echo "      \"memory_percent\": \"$mem\","
                        echo "      \"command\": \"$full_cmd\""
                        echo -n "    }"
                        first=false
                    fi
                fi
            fi
        done < <(lsof -i -P -n 2>/dev/null)
    fi
    
    echo ""
    echo "  ]"
    echo "}"
}

# Function to find processes using specific ports
find_port_processes() {
    local ports=("$@")
    local all_pids=()
    
    if [ "$JSON_OUTPUT" = true ]; then
        echo "{"
        echo "  \"results\": ["
    fi
    
    for port in "${ports[@]}"; do
        if [ "$QUIET" = false ] && [ "$JSON_OUTPUT" = false ]; then
            echo -e "${BLUE}=== Port $port ===${NC}"
        fi
        
        local found=false
        local port_pids=()
        
        # Get PIDs for this port
        if command -v lsof &> /dev/null; then
            while IFS= read -r pid; do
                if [ -n "$pid" ]; then
                    port_pids+=("$pid")
                    all_pids+=("$pid")
                    found=true
                fi
            done < <(lsof -t -i :$port 2>/dev/null)
        fi
        
        if [ "$found" = true ]; then
            if [ "$JSON_OUTPUT" = true ]; then
                if [ ${#all_pids[@]} -gt 1 ]; then echo ","; fi
                echo "    {"
                echo "      \"port\": $port,"
                echo "      \"processes\": ["
            fi
            
            local first_process=true
            for pid in "${port_pids[@]}"; do
                if ps -p "$pid" > /dev/null 2>&1; then
                    local proc_info=$(get_process_info "$pid")
                    local user=$(echo "$proc_info" | cut -d',' -f1)
                    local process=$(echo "$proc_info" | cut -d',' -f2)
                    local full_cmd=$(echo "$proc_info" | cut -d',' -f3)
                    local cpu=$(echo "$proc_info" | cut -d',' -f4)
                    local mem=$(echo "$proc_info" | cut -d',' -f5)
                    
                    if should_include_process "$pid" "$process" "$user"; then
                        if [ "$JSON_OUTPUT" = true ]; then
                            if [ "$first_process" = false ]; then echo ","; fi
                            echo "        {"
                            echo "          \"pid\": $pid,"
                            echo "          \"user\": \"$user\","
                            echo "          \"process\": \"$process\","
                            echo "          \"cpu_percent\": \"$cpu\","
                            echo "          \"memory_percent\": \"$mem\","
                            echo "          \"command\": \"$full_cmd\""
                            echo -n "        }"
                            first_process=false
                        elif [ "$QUIET" = false ]; then
                            echo -e "${YELLOW}PID: $pid | User: $user | Process: $process | CPU: $cpu% | Mem: $mem%${NC}"
                            echo -e "${CYAN}Command: $full_cmd${NC}"
                        fi
                    fi
                fi
            done
            
            if [ "$JSON_OUTPUT" = true ]; then
                echo ""
                echo "      ]"
                echo -n "    }"
            fi
        else
            if [ "$JSON_OUTPUT" = true ]; then
                if [ ${#all_pids[@]} -gt 0 ]; then echo ","; fi
                echo "    {"
                echo "      \"port\": $port,"
                echo "      \"processes\": []"
                echo -n "    }"
            elif [ "$QUIET" = false ]; then
                echo -e "${YELLOW}No processes found using port $port${NC}"
            fi
        fi
        
        if [ "$QUIET" = false ] && [ "$JSON_OUTPUT" = false ]; then
            echo ""
        fi
    done
    
    if [ "$JSON_OUTPUT" = true ]; then
        echo ""
        echo "  ]"
        echo "}"
    fi
    
    printf '%s\n' "${all_pids[@]}"
}

# Function to get PIDs for multiple ports
get_multiple_port_pids() {
    local ports=("$@")
    local all_pids=()
    
    for port in "${ports[@]}"; do
        if command -v lsof &> /dev/null; then
            while IFS= read -r pid; do
                if [ -n "$pid" ]; then
                    all_pids+=("$pid")
                fi
            done < <(lsof -t -i :$port 2>/dev/null)
        fi
    done
    
    # Remove duplicates
    printf '%s\n' "${all_pids[@]}" | sort -u
}

# Function to kill processes with enhanced options
kill_processes() {
    local ports=("$@")
    local pids=($(get_multiple_port_pids "${ports[@]}"))
    
    if [ ${#pids[@]} -eq 0 ]; then
        if [ "$QUIET" = false ]; then
            echo -e "${YELLOW}No processes found to kill on specified ports${NC}"
        fi
        return 1
    fi
    
    # Filter PIDs based on criteria
    local filtered_pids=()
    for pid in "${pids[@]}"; do
        if ps -p "$pid" > /dev/null 2>&1; then
            local proc_info=$(get_process_info "$pid")
            local user=$(echo "$proc_info" | cut -d',' -f1)
            local process=$(echo "$proc_info" | cut -d',' -f2)
            
            if should_include_process "$pid" "$process" "$user"; then
                filtered_pids+=("$pid")
            fi
        fi
    done
    
    if [ ${#filtered_pids[@]} -eq 0 ]; then
        if [ "$QUIET" = false ]; then
            echo -e "${YELLOW}No processes match the specified criteria${NC}"
        fi
        return 1
    fi
    
    if [ "$DRY_RUN" = true ]; then
        if [ "$QUIET" = false ]; then
            echo -e "${CYAN}${BOLD}DRY RUN - Would kill the following processes:${NC}"
        fi
        for pid in "${filtered_pids[@]}"; do
            local proc_info=$(get_process_info "$pid")
            local user=$(echo "$proc_info" | cut -d',' -f1)
            local process=$(echo "$proc_info" | cut -d',' -f2)
            local full_cmd=$(echo "$proc_info" | cut -d',' -f3)
            if [ "$QUIET" = false ]; then
                echo -e "${YELLOW}PID $pid ($user): $process - $full_cmd${NC}"
            fi
        done
        return 0
    fi
    
    if [ "$QUIET" = false ]; then
        echo -e "${RED}Found ${#filtered_pids[@]} process(es) to kill${NC}"
        
        # Show process details
        for pid in "${filtered_pids[@]}"; do
            local proc_info=$(get_process_info "$pid")
            local user=$(echo "$proc_info" | cut -d',' -f1)
            local process=$(echo "$proc_info" | cut -d',' -f2)
            local full_cmd=$(echo "$proc_info" | cut -d',' -f3)
            local cpu=$(echo "$proc_info" | cut -d',' -f4)
            local mem=$(echo "$proc_info" | cut -d',' -f5)
            echo -e "${YELLOW}PID $pid ($user): $process [CPU: $cpu%, Mem: $mem%]${NC}"
            echo -e "${CYAN}  Command: $full_cmd${NC}"
        done
        echo ""
    fi
    
    # Confirmation logic
    local confirm="n"
    if [ "$AUTO_CONFIRM" = true ]; then
        confirm="y"
    elif [ "$CONFIRMATION_TIMEOUT" -gt 0 ]; then
        if [ "$QUIET" = false ]; then
            echo -e "${RED}Auto-confirming in $CONFIRMATION_TIMEOUT seconds... (Ctrl+C to cancel)${NC}"
        fi
        sleep "$CONFIRMATION_TIMEOUT"
        confirm="y"
    else
        if [ "$QUIET" = false ]; then
            local kill_type="kill"
            if [ "$FORCE_KILL" = true ]; then
                kill_type="force kill (SIGKILL)"
            fi
            read -p "Do you want to $kill_type these processes? (y/N): " confirm
        fi
    fi
    
    if [[ $confirm =~ ^[Yy]$ ]]; then
        local killed=0
        local signal="TERM"
        if [ "$FORCE_KILL" = true ]; then
            signal="KILL"
        fi
        
        for pid in "${filtered_pids[@]}"; do
            if ps -p "$pid" > /dev/null 2>&1; then
                if kill -s "$signal" "$pid" 2>/dev/null; then
                    if [ "$QUIET" = false ]; then
                        echo -e "${GREEN}✓ Killed process $pid${NC}"
                    fi
                    ((killed++))
                else
                    if [ "$QUIET" = false ]; then
                        echo -e "${RED}✗ Failed to kill process $pid (try with sudo or --force?)${NC}"
                    fi
                fi
            else
                if [ "$QUIET" = false ]; then
                    echo -e "${YELLOW}! Process $pid already terminated${NC}"
                fi
            fi
        done
        
        if [ "$QUIET" = false ]; then
            if [ $killed -gt 0 ]; then
                echo -e "${GREEN}Successfully killed $killed process(es)${NC}"
                
                # Check if ports are now free
                sleep 1
                local ports_still_used=0
                for port in "${ports[@]}"; do
                    if command -v lsof &> /dev/null; then
                        if lsof -i :$port > /dev/null 2>&1; then
                            ((ports_still_used++))
                        fi
                    fi
                done
                
                if [ $ports_still_used -eq 0 ]; then
                    echo -e "${GREEN}All specified ports are now free${NC}"
                else
                    echo -e "${YELLOW}Some ports might still be in use${NC}"
                fi
            fi
        fi
    else
        if [ "$QUIET" = false ]; then
            echo -e "${YELLOW}Operation cancelled${NC}"
        fi
    fi
}

# Function to save port list
save_port_list() {
    local name="$1"
    local ports="$2"
    
    # Create config file if it doesn't exist
    touch "$CONFIG_FILE"
    
    # Remove existing entry with same name
    grep -v "^$name:" "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" 2>/dev/null || true
    mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    
    # Add new entry
    echo "$name:$ports" >> "$CONFIG_FILE"
    echo -e "${GREEN}Saved port list '$name': $ports${NC}"
}

# Function to load port list
load_port_list() {
    local name="$1"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}No saved port lists found${NC}"
        return 1
    fi
    
    local ports=$(grep "^$name:" "$CONFIG_FILE" | cut -d':' -f2)
    if [ -n "$ports" ]; then
        echo "$ports"
    else
        echo -e "${RED}Port list '$name' not found${NC}"
        return 1
    fi
}

# Function to list saved port lists
list_saved_ports() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${YELLOW}No saved port lists found${NC}"
        return
    fi
    
    echo -e "${BLUE}${BOLD}Saved Port Lists:${NC}"
    while IFS=':' read -r name ports; do
        echo -e "${YELLOW}$name:${NC} $ports"
    done < "$CONFIG_FILE"
}

# Interactive mode with enhancements
interactive_mode() {
    while true; do
        clear
        echo -e "${GREEN}${BOLD}=== Port Kill v$VERSION - Interactive Mode ===${NC}"
        
        if [ "$WATCH_MODE" = true ]; then
            list_all_ports
            sleep 2
        else
            list_all_ports
            echo ""
            echo -e "${BLUE}Options:${NC}"
            echo "1. Enter port number(s) to manage"
            echo "2. Load saved port list"
            echo "3. Toggle filters"
            echo "4. Refresh list"
            echo "5. Watch mode (auto-refresh)"
            echo "6. Exit"
            echo ""
            read -p "Choose an option (1-6): " choice
            
            case $choice in
                1)
                    read -p "Enter port(s) [single/range/comma-separated]: " port_input
                    if [ -n "$port_input" ]; then
                        local ports=($(parse_ports "$port_input"))
                        if [ ${#ports[@]} -gt 0 ]; then
                            echo ""
                            find_port_processes "${ports[@]}" > /dev/null
                            echo ""
                            read -p "Save this port list? (y/N): " save_confirm
                            if [[ $save_confirm =~ ^[Yy]$ ]]; then
                                read -p "Enter name for port list: " list_name
                                if [ -n "$list_name" ]; then
                                    save_port_list "$list_name" "$port_input"
                                fi
                            fi
                            echo ""
                            read -p "Kill processes? (y/N): " kill_confirm
                            if [[ $kill_confirm =~ ^[Yy]$ ]]; then
                                kill_processes "${ports[@]}"
                            fi
                        else
                            echo -e "${RED}Invalid port format${NC}"
                        fi
                        read -p "Press Enter to continue..."
                    fi
                    ;;
                2)
                    list_saved_ports
                    echo ""
                    read -p "Enter port list name to load: " list_name
                    if [ -n "$list_name" ]; then
                        local saved_ports=$(load_port_list "$list_name")
                        if [ $? -eq 0 ]; then
                            local ports=($(parse_ports "$saved_ports"))
                            echo ""
                            find_port_processes "${ports[@]}" > /dev/null
                            echo ""
                            read -p "Kill processes? (y/N): " kill_confirm
                            if [[ $kill_confirm =~ ^[Yy]$ ]]; then
                                kill_processes "${ports[@]}"
                            fi
                        fi
                        read -p "Press Enter to continue..."
                    fi
                    ;;
                3)
                    echo -e "${BLUE}Current Filters:${NC}"
                    echo "Force Kill: $FORCE_KILL"
                    echo "Dry Run: $DRY_RUN"
                    echo "Only Processes: ${ONLY_PROCESSES[*]}"
                    echo "Exclude Processes: ${EXCLUDE_PROCESSES[*]}"
                    echo "Exclude Users: ${EXCLUDE_USERS[*]}"
                    echo ""
                    read -p "Toggle force kill? (y/N): " toggle
                    if [[ $toggle =~ ^[Yy]$ ]]; then
                        if [ "$FORCE_KILL" = true ]; then
                            FORCE_KILL=false
                        else
                            FORCE_KILL=true
                        fi
                    fi
                    read -p "Press Enter to continue..."
                    ;;
                4)
                    # Just continue the loop to refresh
                    ;;
                5)
                    WATCH_MODE=true
                    echo -e "${GREEN}Watch mode enabled. Press Ctrl+C to exit.${NC}"
                    ;;
                6)
                    echo -e "${GREEN}Goodbye!${NC}"
                    exit 0
                    ;;
                *)
                    echo -e "${RED}Invalid option${NC}"
                    read -p "Press Enter to continue..."
                    ;;
            esac
        fi
    done
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                FORCE_KILL=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -q|--quiet)
                QUIET=true
                shift
                ;;
            -w|--watch)
                WATCH_MODE=true
                shift
                ;;
            -j|--json)
                JSON_OUTPUT=true
                QUIET=true
                shift
                ;;
            -y|--yes)
                AUTO_CONFIRM=true
                shift
                ;;
            -t|--timeout)
                CONFIRMATION_TIMEOUT="$2"
                shift 2
                ;;
            --only)
                IFS=',' read -ra ONLY_PROCESSES <<< "$2"
                shift 2
                ;;
            --exclude)
                IFS=',' read -ra EXCLUDE_PROCESSES <<< "$2"
                shift 2
                ;;
            --exclude-users)
                IFS=',' read -ra EXCLUDE_USERS <<< "$2"
                shift 2
                ;;
            --save-list)
                SAVE_LIST_NAME="$2"
                shift 2
                ;;
            --load-list)
                LOAD_LIST_NAME="$2"
                shift 2
                ;;
            --list-saved)
                list_saved_ports
                exit 0
                ;;
            --common)
                show_common_ports
                exit 0
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            -*)
                echo -e "${RED}Unknown option: $1${NC}"
                show_usage
                exit 1
                ;;
            *)
                PORT_ARGS="$1"
                shift
                ;;
        esac
    done
}

# Main function
main() {
    parse_args "$@"
    
    # Handle load list option
    if [ -n "$LOAD_LIST_NAME" ]; then
        local saved_ports=$(load_port_list "$LOAD_LIST_NAME")
        if [ $? -eq 0 ]; then
            PORT_ARGS="$saved_ports"
        else
            exit 1
        fi
    fi
    
    # Check if running as root
    if [ $EUID -eq 0 ] && [ "$QUIET" = false ]; then
        echo -e "${YELLOW}Running as root - you can kill any process${NC}"
    fi
    
    # Handle watch mode for all ports
    if [ "$WATCH_MODE" = true ] && [ -z "$PORT_ARGS" ]; then
        if [ "$QUIET" = false ]; then
            echo -e "${GREEN}=== Watch Mode - Press Ctrl+C to exit ===${NC}"
        fi
        while true; do
            clear
            if [ "$QUIET" = false ]; then
                echo -e "${BLUE}$(date)${NC}"
            fi
            list_all_ports > /dev/null
            sleep 3
        done
    fi
    
    # No arguments - interactive mode
    if [ -z "$PORT_ARGS" ]; then
        interactive_mode
        exit 0
    fi
    
    # Parse port arguments
    local ports=($(parse_ports "$PORT_ARGS"))
    
    if [ ${#ports[@]} -eq 0 ]; then
        echo -e "${RED}Error: No valid ports specified${NC}"
        echo -e "${BLUE}Valid formats: 8080, 8000-8010, 8080,3000,5432${NC}"
        exit 1
    fi
    
    # Save list if requested
    if [ -n "$SAVE_LIST_NAME" ]; then
        save_port_list "$SAVE_LIST_NAME" "$PORT_ARGS"
    fi
    
    # Handle watch mode for specific ports
    if [ "$WATCH_MODE" = true ]; then
        if [ "$QUIET" = false ]; then
            echo -e "${GREEN}=== Watch Mode for ports: ${ports[*]} - Press Ctrl+C to exit ===${NC}"
        fi
        while true; do
            clear
            if [ "$QUIET" = false ]; then
                echo -e "${BLUE}$(date)${NC}"
            fi
            find_port_processes "${ports[@]}" > /dev/null
            sleep 3
        done
    fi
    
    # Regular mode - find and optionally kill processes
    if [ "$QUIET" = false ] && [ "$JSON_OUTPUT" = false ]; then
        echo -e "${GREEN}=== Port Kill v$VERSION ===${NC}"
        if [ ${#ports[@]} -eq 1 ]; then
            echo -e "${BLUE}Managing port: ${ports[0]}${NC}"
        else
            echo -e "${BLUE}Managing ports: ${ports[*]}${NC}"
        fi
        
        # Show active filters
        local filters=()
        [ "$FORCE_KILL" = true ] && filters+=("Force Kill")
        [ "$DRY_RUN" = true ] && filters+=("Dry Run")
        [ ${#ONLY_PROCESSES[@]} -gt 0 ] && filters+=("Only: ${ONLY_PROCESSES[*]}")
        [ ${#EXCLUDE_PROCESSES[@]} -gt 0 ] && filters+=("Exclude: ${EXCLUDE_PROCESSES[*]}")
        [ ${#EXCLUDE_USERS[@]} -gt 0 ] && filters+=("Exclude Users: ${EXCLUDE_USERS[*]}")
        
        if [ ${#filters[@]} -gt 0 ]; then
            echo -e "${CYAN}Active filters: ${filters[*]}${NC}"
        fi
        echo ""
    fi
    
    # Find processes
    local pids=($(find_port_processes "${ports[@]}"))
    
    if [ ${#pids[@]} -gt 0 ] && [ "$JSON_OUTPUT" = false ]; then
        if [ "$DRY_RUN" = false ]; then
            kill_processes "${ports[@]}"
        fi
    fi
}

# Trap Ctrl+C for clean exit in watch mode
trap 'echo -e "\n${GREEN}Exiting...${NC}"; exit 0' INT

# Run main function with all arguments
main "$@"
