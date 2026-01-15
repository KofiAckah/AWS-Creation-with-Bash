#!/bin/bash

# Logging utility functions following best practices
# Source: https://grahamwatts.co.uk/bash-logging/

# Color codes for terminal output
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Log levels
readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_WARN=2
readonly LOG_LEVEL_ERROR=3
readonly LOG_LEVEL_FATAL=4

# Default log level (can be overridden by environment variable)
LOG_LEVEL=${LOG_LEVEL:-$LOG_LEVEL_INFO}

# Get log file from config or use default
LOG_FILE=${LOG_FILE:-"setup.log"}

# Initialize log file with header
init_logging() {
    # Create log file if it doesn't exist
    if [ ! -f "$LOG_FILE" ]; then
        touch "$LOG_FILE"
    fi
    
    # Write session header
    {
        echo ""
        echo "=========================================="
        echo "Log Session Started: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Script: ${BASH_SOURCE[1]}"
        echo "User: $(whoami)"
        echo "Region: ${REGION:-Not Set}"
        echo "=========================================="
        echo ""
    } >> "$LOG_FILE"
}

# Core logging function
_log() {
    local level=$1
    local level_name=$2
    local color=$3
    local message=$4
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local caller="${BASH_SOURCE[2]##*/}:${BASH_LINENO[1]}"
    
    # Check if we should log this level
    if [ "$level" -lt "$LOG_LEVEL" ]; then
        return 0
    fi
    
    # Format log message
    local log_message="[$timestamp] [$level_name] [$caller] $message"
    local terminal_message="${color}[$timestamp] [$level_name]${NC} $message"
    
    # Write to log file (no color codes)
    echo "$log_message" >> "$LOG_FILE"
    
    # Output to terminal with colors
    echo -e "$terminal_message"
}

# Log level functions
log_debug() {
    _log $LOG_LEVEL_DEBUG "DEBUG" "$CYAN" "$1"
}

log_info() {
    _log $LOG_LEVEL_INFO "INFO" "$GREEN" "$1"
}

log_warn() {
    _log $LOG_LEVEL_WARN "WARN" "$YELLOW" "$1"
}

log_error() {
    _log $LOG_LEVEL_ERROR "ERROR" "$RED" "$1"
}

log_fatal() {
    _log $LOG_LEVEL_FATAL "FATAL" "$RED" "$1"
    exit 1
}

# Function to log command execution
log_command() {
    local cmd="$1"
    log_debug "Executing: $cmd"
}

# Function to execute AWS command with dry run support
run_aws_command() {
    local description="$1"
    shift
    local cmd=("$@")
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would execute: $description"
        log_debug "[DRY RUN] Command: ${cmd[*]}"
        return 0
    else
        log_debug "Executing: ${cmd[*]}"
        "${cmd[@]}"
        return $?
    fi
}

# Function to save state to .env file
save_state() {
    local key=$1
    local value=$2
    local state_file="${STATE_FILE:-.env}"
    
    log_debug "Saving state: $key=$value"
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would save state: $key=$value"
        return 0
    fi
    
    # Create state file if it doesn't exist
    touch "$state_file"
    
    # Remove existing entry if present
    if grep -q "^${key}=" "$state_file" 2>/dev/null; then
        sed -i "/^${key}=/d" "$state_file"
        log_debug "Removed existing entry for $key"
    fi
    
    # Add new entry
    echo "${key}=${value}" >> "$state_file"
    log_info "State saved: $key=$value"
}

# Function to load state from .env file
load_state() {
    local key=$1
    local state_file="${STATE_FILE:-.env}"
    
    if [ ! -f "$state_file" ]; then
        log_warn "State file not found: $state_file"
        return 1
    fi
    
    # Get value and strip ANSI color codes
    local value=$(grep "^${key}=" "$state_file" 2>/dev/null | cut -d'=' -f2- | sed 's/\x1b\[[0-9;]*m//g')
    
    if [ -z "$value" ]; then
        log_warn "Key not found in state file: $key"
        return 1
    fi
    
    echo "$value"
}

# Function to get value from state file, removing any ANSI color codes
get_from_state() {
    local key=$1
    if [ -f "$STATE_FILE" ]; then
        # Remove any ANSI color codes from the value
        local value=$(grep "^${key}=" "$STATE_FILE" 2>/dev/null | cut -d'=' -f2- | sed 's/\x1b\[[0-9;]*m//g')
        if [ -n "$value" ]; then
            echo "$value"
            return 0
        fi
    fi
    log_warn "Key not found in state file: $key"
    return 1
}

# Function to check if AWS CLI is installed
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        log_fatal "AWS CLI is not installed. Please install it first."
    fi
    log_info "AWS CLI found: $(aws --version)"
}

# Function to check AWS credentials
check_aws_credentials() {
    log_info "Checking AWS credentials..."
    
    if ! aws sts get-caller-identity &> /dev/null; then
        log_fatal "AWS credentials not configured. Run 'aws configure' first."
    fi
    
    local identity=$(aws sts get-caller-identity --output json 2>/dev/null)
    local account=$(echo "$identity" | grep -o '"Account": "[^"]*"' | cut -d'"' -f4)
    local user=$(echo "$identity" | grep -o '"Arn": "[^"]*"' | cut -d'"' -f4 | rev | cut -d'/' -f1 | rev)
    
    log_info "AWS Account: $account"
    log_info "AWS User: $user"
}

# Function to validate region
validate_region() {
    local region=$1
    
    log_info "Validating AWS region: $region"
    
    # Simple check - just verify we can make API calls to this region
    if aws ec2 describe-availability-zones --region "$region" &> /dev/null; then
        log_info "Region validated: $region"
        return 0
    else
        log_fatal "Invalid AWS region or no access: $region"
    fi
}

# Function to validate CIDR block
validate_cidr() {
    local cidr=$1
    local name=$2
    
    log_debug "Validating CIDR block: $cidr ($name)"
    
    # Basic CIDR validation regex
    if ! echo "$cidr" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$'; then
        log_error "Invalid CIDR format: $cidr ($name)"
        return 1
    fi
    
    log_debug "CIDR block validated: $cidr"
    return 0
}

# Function to handle AWS CLI errors
handle_aws_error() {
    local exit_code=$1
    local command=$2
    
    if [ $exit_code -ne 0 ]; then
        log_error "AWS command failed with exit code $exit_code"
        log_error "Command: $command"
        return 1
    fi
    
    return 0
}

# Function to display summary
log_summary() {
    local title=$1
    shift
    local items=("$@")
    
    echo "" | tee -a "$LOG_FILE"
    log_info "=========================================="
    log_info "$title"
    log_info "=========================================="
    
    for item in "${items[@]}"; do
        log_info "$item"
    done
    
    log_info "=========================================="
    echo "" | tee -a "$LOG_FILE"
}

# Function to start a section
log_section() {
    local section_name=$1
    echo "" | tee -a "$LOG_FILE"
    log_info ">>> Starting: $section_name"
}

# Function to end a section
log_section_end() {
    local section_name=$1
    local status=$2
    
    if [ "$status" = "success" ]; then
        log_info "<<< Completed: $section_name [SUCCESS]"
    else
        log_error "<<< Completed: $section_name [FAILED]"
    fi
    echo "" | tee -a "$LOG_FILE"
}

# Export functions so they can be used in other scripts
export -f init_logging
export -f _log
export -f log_debug
export -f log_info
export -f log_warn
export -f log_error
export -f log_fatal
export -f log_command
export -f run_aws_command
export -f save_state
export -f load_state
export -f check_aws_cli
export -f check_aws_credentials
export -f validate_region
export -f validate_cidr
export -f handle_aws_error
export -f log_summary
export -f log_section
export -f log_section_end

# Initialize logging when sourced
init_logging

# Display dry run mode if enabled
if [ "$DRY_RUN" = "true" ]; then
    log_warn "=========================================="
    log_warn "DRY RUN MODE ENABLED"
    log_warn "No actual resources will be created"
    log_warn "=========================================="
fi