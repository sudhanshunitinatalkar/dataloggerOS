#!/usr/bin/env bash

# ==============================================================================
# INDUSTRIAL DATALOGGER BOOTSTRAP SCRIPT
# Location: ~/dataloggerOS/datalogger_run.sh
# Function: 
#   1. KILLS any existing/stale datalogger processes (Anti-Duplication).
#   2. Auto-updates git repository.
#   3. Launches a single Nix environment.
#   4. Spawns 7 parallel Python processes with self-healing (auto-restart) logic.
# ==============================================================================

# --- CONFIGURATION ---
REPO_DIR="$HOME/datalogger"
REPO_URL="https://github.com/sudhanshunitinatalkar/datalogger.git"
LOG_DIR="$HOME/datalogger_logs"
BOOT_LOG="$LOG_DIR/boot_system.log"

# List of specific script names to target for cleanup
TARGET_SCRIPTS="configure|cpcb|data|datalogger|display|network|saicloud"

# --- PRE-FLIGHT CHECKS ---
mkdir -p "$LOG_DIR"

# Helper function to log strictly to file (No Terminal Output)
log_msg() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [SYSTEM] $1" >> "$BOOT_LOG"
}

log_msg "=== BOOT SEQUENCE INITIATED ==="

# --- STEP 0: CLEANUP STALE PROCESSES (The Fix) ---
log_msg "Ensuring no duplicate processes are running..."
# We use pgrep/pkill with the -f (full command line) flag to find our specific python scripts.
if pgrep -f "python.*($TARGET_SCRIPTS)\.py" > /dev/null; then
    log_msg "Found stale processes. Killing them now..."
    pkill -f "python.*($TARGET_SCRIPTS)\.py"
    sleep 2
    # Double tap to be sure
    pkill -9 -f "python.*($TARGET_SCRIPTS)\.py"
else
    log_msg "No stale processes found. Clean start."
fi

# --- STEP 1: GIT AUTO-UPDATE ---
if [ ! -d "$REPO_DIR" ]; then
    log_msg "Repository missing. Cloning from source..."
    if git clone -b dev "$REPO_URL" "$REPO_DIR" >> "$BOOT_LOG" 2>&1; then
        log_msg "Clone successful."
    else
        log_msg "CRITICAL FAILURE: Could not clone repository. Check internet/URL."
        exit 1
    fi
else
    log_msg "Repository found. Checking for updates..."
    (
        cd "$REPO_DIR" || exit
        if git pull >> "$BOOT_LOG" 2>&1; then
            log_msg "Update successful (Git Pull)."
        else
            log_msg "WARNING: Git pull failed (Network down?). Proceeding with existing code."
        fi
    )
fi

# --- STEP 2: DEFINE SUPERVISOR LOGIC ---
# This script block runs INSIDE the Nix environment.
SUPERVISOR_SCRIPT=$(cat << 'EOF'
    # List of modules to run simultaneously
    SCRIPTS=("configure" "cpcb" "data" "datalogger" "display" "network" "saicloud")
    LOG_DIR="$HOME/datalogger_logs"
    REPO_ROOT="$HOME/datalogger"

    echo "Starting Process Supervisor inside Nix Environment..."

    # Function: Watchdog for a single service
    start_watchdog() {
        local name=$1
        local script_path="$REPO_ROOT/src/${name}.py"
        local service_log="$LOG_DIR/${name}_runtime.log"

        # Infinite Loop for Self-Healing
        while true; do
            # Log start attempt
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting Service: $name" >> "$service_log"
            
            # Run Python Script
            python "$script_path" >> "$service_log" 2>&1
            
            # If we reach here, the script has crashed/exited
            EXIT_CODE=$?
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] CRASH: $name exited with code $EXIT_CODE" >> "$service_log"
            
            # Delay to prevent CPU thrashing
            echo "Restarting in 3 seconds..." >> "$service_log"
            sleep 3
        done
    }

    # Launch all watchdogs in the background
    for script_name in "${SCRIPTS[@]}"; do
        start_watchdog "$script_name" &
    done

    # IMPORTANT: Wait strictly keeps the parent shell alive.
    wait
EOF
)

# --- STEP 3: EXECUTE NIX ENVIRONMENT ---
log_msg "Launching Nix Develop Environment..."

# We switch to the repo dir so Nix finds the flake.nix
cd "$REPO_DIR" || { log_msg "CRITICAL: Cannot enter repo dir"; exit 1; }

# Run nix develop. 
nix develop . --command bash -c "$SUPERVISOR_SCRIPT" >> "$BOOT_LOG" 2>&1

log_msg "CRITICAL: Nix environment exited unexpectedly. Service Stopping."