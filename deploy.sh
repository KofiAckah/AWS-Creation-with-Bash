#!/bin/bash

# AWS Infrastructure Deployment Orchestrator
# This script orchestrates the complete deployment of AWS infrastructure
# by running all creation scripts in the correct dependency order

# Source the configuration and utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/utils.sh"

# Script execution order
SCRIPTS=(
    "create_key_pair.sh"
    "create_network.sh"
    "create_security_group.sh"
    "create_ec2.sh"
    "create_s3_bucket.sh"
)

# Script descriptions
declare -A SCRIPT_DESCRIPTIONS=(
    ["create_key_pair.sh"]="Create EC2 Key Pair"
    ["create_network.sh"]="Create VPC and Network Infrastructure"
    ["create_security_group.sh"]="Create Security Group"
    ["create_ec2.sh"]="Create EC2 Instance with Web Server"
    ["create_s3_bucket.sh"]="Create S3 Bucket and Upload Files"
)

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

AWS Infrastructure Deployment Orchestrator

This script automates the complete deployment of AWS infrastructure by running
all creation scripts in the correct dependency order.

OPTIONS:
    -d, --dry-run       Preview what would be deployed without creating resources
    -h, --help          Display this help message
    -s, --skip SCRIPT   Skip a specific script (can be used multiple times)
    -o, --only SCRIPT   Only run a specific script
    -v, --verbose       Enable verbose (DEBUG) logging

EXAMPLES:
    # Deploy all infrastructure
    ./deploy.sh

    # Preview deployment without creating resources
    ./deploy.sh --dry-run

    # Deploy everything except S3 bucket
    ./deploy.sh --skip create_s3_bucket.sh

    # Only deploy network infrastructure
    ./deploy.sh --only create_network.sh

    # Deploy with verbose logging
    ./deploy.sh --verbose

SCRIPTS EXECUTION ORDER:
EOF
    
    local i=1
    for script in "${SCRIPTS[@]}"; do
        echo "    $i. $script - ${SCRIPT_DESCRIPTIONS[$script]}"
        ((i++))
    done
    
    cat << EOF

NOTES:
    - All scripts must be executable (chmod +x *.sh)
    - AWS CLI must be configured with valid credentials
    - Resources are tracked in .env state file
    - Logs are written to setup.log
    - Scripts are idempotent and safe to re-run

EOF
}

# Function to check if a script exists and is executable
check_script() {
    local script=$1
    local script_path="${SCRIPT_DIR}/${script}"
    
    if [ ! -f "$script_path" ]; then
        log_error "Script not found: $script"
        return 1
    fi
    
    if [ ! -x "$script_path" ]; then
        log_warn "Script not executable: $script. Attempting to make it executable..."
        chmod +x "$script_path"
        if [ $? -ne 0 ]; then
            log_error "Failed to make script executable: $script"
            return 1
        fi
        log_info "Script is now executable: $script"
    fi
    
    return 0
}

# Function to run a script
run_script() {
    local script=$1
    local script_path="${SCRIPT_DIR}/${script}"
    
    log_section "Running: $script"
    log_info "Description: ${SCRIPT_DESCRIPTIONS[$script]}"
    
    # Check if script exists and is executable
    if ! check_script "$script"; then
        log_section_end "Running: $script" "failed"
        return 1
    fi
    
    # Run the script
    log_info "Executing: $script_path"
    bash "$script_path"
    local exit_code=$?
    
    if [ $exit_code -ne 0 ]; then
        log_error "Script failed with exit code: $exit_code"
        log_section_end "Running: $script" "failed"
        return 1
    fi
    
    log_section_end "Running: $script" "success"
    return 0
}

# Function to display deployment summary
display_summary() {
    log_info ""
    log_info "=========================================="
    log_info "Deployment Summary"
    log_info "=========================================="
    
    if [ -f "$STATE_FILE" ]; then
        log_info "State file: $STATE_FILE"
        log_info ""
        log_info "Created Resources:"
        
        # Display all state variables
        while IFS='=' read -r key value; do
            if [ -n "$key" ] && [ -n "$value" ]; then
                log_info "  $key: $value"
            fi
        done < "$STATE_FILE"
    else
        log_warn "State file not found: $STATE_FILE"
    fi
    
    log_info ""
    log_info "Log file: $LOG_FILE"
    log_info "=========================================="
    log_info ""
}

# Function to display deployment plan
display_plan() {
    log_info "=========================================="
    log_info "Deployment Plan"
    log_info "=========================================="
    log_info ""
    log_info "The following scripts will be executed in order:"
    log_info ""
    
    local i=1
    for script in "${SCRIPTS[@]}"; do
        if [[ ! " ${SKIP_SCRIPTS[@]} " =~ " ${script} " ]]; then
            log_info "  $i. $script"
            log_info "     ${SCRIPT_DESCRIPTIONS[$script]}"
            log_info ""
            ((i++))
        fi
    done
    
    log_info "=========================================="
    log_info ""
}

# Parse command line arguments
SKIP_SCRIPTS=()
ONLY_SCRIPT=""
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--dry-run)
            export DRY_RUN=true
            log_info "Dry run mode enabled"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -s|--skip)
            if [ -z "$2" ] || [[ "$2" == -* ]]; then
                log_error "Option --skip requires a script name"
                exit 1
            fi
            SKIP_SCRIPTS+=("$2")
            shift 2
            ;;
        -o|--only)
            if [ -z "$2" ] || [[ "$2" == -* ]]; then
                log_error "Option --only requires a script name"
                exit 1
            fi
            ONLY_SCRIPT="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            export LOG_LEVEL=$LOG_LEVEL_DEBUG
            log_info "Verbose logging enabled"
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Main execution
main() {
    log_info "=========================================="
    log_info "AWS Infrastructure Deployment Orchestrator"
    log_info "=========================================="
    log_info "Started at: $(date '+%Y-%m-%d %H:%M:%S')"
    log_info "Region: $REGION"
    
    if [ "$DRY_RUN" = "true" ]; then
        log_warn "DRY RUN MODE: No resources will be created"
    fi
    
    log_info ""
    
    # Pre-flight checks
    log_section "Pre-flight Checks"
    check_aws_cli
    check_aws_credentials
    validate_region "$REGION"
    log_section_end "Pre-flight Checks" "success"
    
    # Initialize state file
    if [ ! -f "$STATE_FILE" ]; then
        touch "$STATE_FILE"
        log_info "Created state file: $STATE_FILE"
    fi
    
    # Determine which scripts to run
    local scripts_to_run=()
    
    if [ -n "$ONLY_SCRIPT" ]; then
        # Only run specified script
        if [[ " ${SCRIPTS[@]} " =~ " ${ONLY_SCRIPT} " ]]; then
            scripts_to_run=("$ONLY_SCRIPT")
            log_info "Running only: $ONLY_SCRIPT"
        else
            log_fatal "Script not found in deployment order: $ONLY_SCRIPT"
        fi
    else
        # Run all scripts except skipped ones
        for script in "${SCRIPTS[@]}"; do
            if [[ ! " ${SKIP_SCRIPTS[@]} " =~ " ${script} " ]]; then
                scripts_to_run+=("$script")
            else
                log_info "Skipping: $script"
            fi
        done
    fi
    
    # Display deployment plan
    if [ ${#scripts_to_run[@]} -gt 0 ]; then
        display_plan
        
        # Ask for confirmation if not in dry run mode
        if [ "$DRY_RUN" != "true" ]; then
            echo -n "Do you want to proceed with the deployment? (yes/no): "
            read -r confirmation
            
            if [ "$confirmation" != "yes" ] && [ "$confirmation" != "y" ]; then
                log_info "Deployment cancelled by user"
                exit 0
            fi
            log_info "Deployment confirmed. Proceeding..."
            log_info ""
        fi
    else
        log_warn "No scripts to run"
        exit 0
    fi
    
    # Run scripts
    local failed_scripts=()
    local successful_scripts=()
    
    for script in "${scripts_to_run[@]}"; do
        if run_script "$script"; then
            successful_scripts+=("$script")
        else
            failed_scripts+=("$script")
            log_error "Deployment failed at: $script"
            
            # Ask if user wants to continue
            if [ "$DRY_RUN" != "true" ]; then
                echo -n "Do you want to continue with remaining scripts? (yes/no): "
                read -r continue_deployment
                
                if [ "$continue_deployment" != "yes" ] && [ "$continue_deployment" != "y" ]; then
                    log_info "Deployment aborted by user"
                    break
                fi
            else
                log_info "Continuing with remaining scripts (dry run mode)..."
            fi
        fi
    done
    
    # Display results
    log_info ""
    log_info "=========================================="
    log_info "Deployment Results"
    log_info "=========================================="
    log_info "Completed at: $(date '+%Y-%m-%d %H:%M:%S')"
    log_info ""
    
    if [ ${#successful_scripts[@]} -gt 0 ]; then
        log_info "Successful scripts (${#successful_scripts[@]}):"
        for script in "${successful_scripts[@]}"; do
            log_info "  ✓ $script"
        done
        log_info ""
    fi
    
    if [ ${#failed_scripts[@]} -gt 0 ]; then
        log_error "Failed scripts (${#failed_scripts[@]}):"
        for script in "${failed_scripts[@]}"; do
            log_error "  ✗ $script"
        done
        log_info ""
    fi
    
    # Display summary
    display_summary
    
    # Exit with appropriate code
    if [ ${#failed_scripts[@]} -gt 0 ]; then
        log_error "Deployment completed with errors"
        exit 1
    else
        log_info "Deployment completed successfully!"
        
        # Display next steps if not in dry run mode
        if [ "$DRY_RUN" != "true" ]; then
            log_info ""
            log_info "Next Steps:"
            log_info "  1. Check resources: ./check_resources.sh"
            log_info "  2. Access web server: http://$(load_state PUBLIC_IP 2>/dev/null || echo '<PUBLIC_IP>')"
            log_info "  3. SSH to instance: ssh -i ${KEY_NAME}.pem ec2-user@$(load_state PUBLIC_IP 2>/dev/null || echo '<PUBLIC_IP>')"
            log_info "  4. View logs: cat $LOG_FILE"
            log_info "  5. Cleanup resources: ./cleanup_resources.sh"
        fi
        
        exit 0
    fi
}

# Run main function
main
