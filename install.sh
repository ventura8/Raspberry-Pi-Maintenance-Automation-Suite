#!/bin/bash
# Description: Interactive installer for the Raspberry Pi Maintenance Suite.
# Fetches scripts, configures email, and allows selective scheduling and timing of tasks.
# Functions as a one-line installer for fresh setups, and a management UI for existing setups.

# --- Configuration ---
GITHUB_USER="ventura8"
REPO_NAME="Raspberry-Pi-Maintenance-Automation-Suite"
BRANCH="main"
RAW_URL="https://raw.githubusercontent.com/$GITHUB_USER/$REPO_NAME/$BRANCH"

INSTALL_DIR="${INSTALL_DIR:-$HOME/pi-scripts}"
SSMTP_CONF="${SSMTP_CONF:-/etc/ssmtp/ssmtp.conf}"
REVALIASES="${REVALIASES:-/etc/ssmtp/revaliases}"

# --- Script Definitions ---
declare -A SCRIPTS
SCRIPTS[1]="update_pi_os.sh"
SCRIPTS[2]="update_pi_firmware.sh"
SCRIPTS[3]="update_pip.sh"
SCRIPTS[4]="docker_cleanup.sh"
SCRIPTS[5]="update_pi_apps.sh"

declare -A NAMES
NAMES[1]="System OS Update"
NAMES[2]="Firmware Update"
NAMES[3]="Python Pip Update"
NAMES[4]="Docker Cleanup"
NAMES[5]="Pi-Apps Update"

# Default Schedules
declare -A DEFAULTS
DEFAULTS[1]="0 3 * * 0"
DEFAULTS[2]="0 2 1 * *"
DEFAULTS[3]="0 4 * * 0"
DEFAULTS[4]="20 4 * * 0"
DEFAULTS[5]="0 5 * * 0"

# --- Helper Functions ---

print_header() {
    clear
    echo "==========================================================="
    echo "      Raspberry Pi Maintenance Suite Manager"
    echo "==========================================================="
    echo ""
}

check_dependencies() {
    echo "Checking dependencies..."
    # Check for ssmtp/mailutils/curl
    if ! command -v ssmtp &> /dev/null || ! command -v curl &> /dev/null; then
        echo "Installing missing dependencies (ssmtp, mailutils, curl)..."
        sudo apt-get update && sudo apt-get install -y ssmtp mailutils curl
    fi
}

cron_to_human() {
    local cron_str=$1
    
    if [[ -z "$cron_str" || "$cron_str" == "-" ]]; then
        echo "-"
        return
    fi

    local m; m=$(echo "$cron_str" | awk '{print $1}')
    local h; h=$(echo "$cron_str" | awk '{print $2}')
    local dom; dom=$(echo "$cron_str" | awk '{print $3}')
    local mon; mon=$(echo "$cron_str" | awk '{print $4}')
    local dow; dow=$(echo "$cron_str" | awk '{print $5}')

    # Pad time
    if [[ ${#m} -eq 1 ]]; then m="0$m"; fi
    if [[ ${#h} -eq 1 ]]; then h="0$h"; fi

    if [[ "$dom" == "*" && "$mon" == "*" && "$dow" == "*" ]]; then
        echo "Daily @ $h:$m"
    elif [[ "$dom" == "*" && "$mon" == "*" && "$dow" != "*" ]]; then
        case $dow in
            0|7) day="Sun" ;;
            1) day="Mon" ;;
            2) day="Tue" ;;
            3) day="Wed" ;;
            4) day="Thu" ;;
            5) day="Fri" ;;
            6) day="Sat" ;;
            *) day="Dow $dow" ;;
        esac
        echo "Weekly $day @ $h:$m"
    elif [[ "$dom" != "*" && "$mon" == "*" && "$dow" == "*" ]]; then
        echo "Monthly $dom @ $h:$m"
    else
        echo "Custom Schedule"
    fi
}

configure_email_interactive() {
    print_header
    echo "--- Email Configuration ---"
    
    local current_user=""
    if [ -f "$SSMTP_CONF" ]; then
        current_user=$(grep "^AuthUser=" "$SSMTP_CONF" | cut -d= -f2)
        echo "Current Configured Email: $current_user"
        read -r -p "Do you want to reconfigure email? [y/N]: " confirm
        [[ ! "$confirm" =~ ^[Yy]$ ]] && return
    fi

    echo ""
    read -r -p "Enter Gmail address: " user_email
    if [[ ! "$user_email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        echo "Invalid email. returning to menu."
        read -r -p "Press Enter..."
        return
    fi

    echo "Enter App Password (16-char, input hidden):"
    read -r -s app_pass
    
    if [ -z "$app_pass" ]; then
        echo "Password empty. Returning."
        return
    fi

    echo "Saving configuration..."
    cat <<EOF | sudo tee "$SSMTP_CONF" > /dev/null
root=$user_email
mailhub=smtp.gmail.com:587
AuthUser=$user_email
AuthPass=$app_pass
UseSTARTTLS=YES
UseTLS=YES
FromLineOverride=YES
hostname=$(hostname)
EOF

    sudo chown root:mail "$SSMTP_CONF"
    sudo chmod 640 "$SSMTP_CONF"
    sudo usermod -a -G mail "$USER"

    cat <<EOF | sudo tee "$REVALIASES" > /dev/null
root:$user_email:smtp.gmail.com:587
$USER:$user_email:smtp.gmail.com:587
EOF
    
    # Update scripts with new email
    if [ -d "$INSTALL_DIR" ]; then
        for file in "$INSTALL_DIR"/*.sh; do
             sed -i "s/RECIPIENT_EMAIL=\".*\"/RECIPIENT_EMAIL=\"$user_email\"/" "$file"
        done
    fi

    echo "Email configured successfully."
    sleep 1
}

show_email_config() {
    print_header
    echo "--- Current Email Settings ---"
    if [ -f "$SSMTP_CONF" ]; then
        user=$(grep "^AuthUser=" "$SSMTP_CONF" | cut -d= -f2)
        hub=$(grep "^mailhub=" "$SSMTP_CONF" | cut -d= -f2)
        echo "User:     $user"
        echo "Server:   $hub"
        echo "Password: [HIDDEN/MASKED]"
    else
        echo "No SSMTP configuration found."
    fi
    echo ""
    read -r -p "Press Enter to return..."
}

download_scripts() {
    echo "Downloading/Updating scripts..."
    mkdir -p "$INSTALL_DIR"
    
    # Get email for injection
    local email_to_inject="your_email@gmail.com"
    if [ -f "$SSMTP_CONF" ]; then
        email_to_inject=$(sudo grep "^AuthUser=" "$SSMTP_CONF" | cut -d= -f2)
    fi

    for i in {1..5}; do
        local script="${SCRIPTS[$i]}"
        # echo "Fetching $script..."
        curl -sSL "$RAW_URL/scripts/$script" -o "$INSTALL_DIR/$script"
        
        if [ -f "$INSTALL_DIR/$script" ]; then
            sed -i "s/your_email@gmail.com/$email_to_inject/g" "$INSTALL_DIR/$script"
            chmod +x "$INSTALL_DIR/$script"
        else
            echo "Error downloading $script"
        fi
    done
    echo "Scripts updated."
    sleep 1
}

get_task_status() {
    local script_name=$1
    local is_root=$2
    local line=""
    
    if [ "$is_root" == "true" ]; then
        line=$(sudo crontab -l 2>/dev/null | grep "$script_name")
    else
        line=$(crontab -l 2>/dev/null | grep "$script_name")
    fi

    if [ -z "$line" ]; then
        echo "DISABLED|-"
    else
        # Extract schedule part (remove the command path)
        local sched; sched=${line% "$INSTALL_DIR"/*}
        echo "ENABLED|$sched"
    fi
}

toggle_task() {
    local id=$1
    local script_name="${SCRIPTS[$id]}"
    local default_sched="${DEFAULTS[$id]}"
    local is_root="true"
    
    # Pi-Apps is the only user-crontab script
    if [ "$script_name" == "update_pi_apps.sh" ]; then
        is_root="false"
    fi

    local status_info; status_info=$(get_task_status "$script_name" "$is_root")
    local state; state=$(echo "$status_info" | cut -d'|' -f1)
    local current_sched; current_sched=$(echo "$status_info" | cut -d'|' -f2)

    echo ""
    echo "Task: ${NAMES[$id]}"
    echo "Current Status: $state"
    if [ "$state" == "ENABLED" ]; then
        echo "Current Schedule: $current_sched"
    fi
    echo ""

    if [ "$state" == "ENABLED" ]; then
        read -r -p "Do you want to DISABLE this task? [y/N] (Enter 'e' to edit time): " choice
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            if [ "$is_root" == "true" ]; then
                sudo crontab -l 2>/dev/null | grep -v "$script_name" | sudo crontab -
            else
                crontab -l 2>/dev/null | grep -v "$script_name" | crontab -
            fi
            echo "Task disabled."
        elif [[ "$choice" =~ ^[Ee]$ ]]; then
             read -r -p "Enter new cron schedule (Default: $default_sched): " new_time
             new_time=${new_time:-$default_sched}
             # Remove old, add new
             if [ "$is_root" == "true" ]; then
                (sudo crontab -l 2>/dev/null | grep -v "$script_name"; echo "$new_time $INSTALL_DIR/$script_name") | sudo crontab -
             else
                (crontab -l 2>/dev/null | grep -v "$script_name"; echo "$new_time $INSTALL_DIR/$script_name") | crontab -
             fi
             echo "Schedule updated."
        fi
    else
        read -r -p "Do you want to ENABLE this task? [y/N]: " choice
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            read -r -p "Enter cron schedule (Default: $default_sched): " new_time
            new_time=${new_time:-$default_sched}
            
            if [ "$is_root" == "true" ]; then
                (sudo crontab -l 2>/dev/null | grep -v "$script_name"; echo "$new_time $INSTALL_DIR/$script_name") | sudo crontab -
            else
                (crontab -l 2>/dev/null | grep -v "$script_name"; echo "$new_time $INSTALL_DIR/$script_name") | crontab -
            fi
            echo "Task enabled."
        fi
    fi
    sleep 1
}

manage_tasks_ui() {
    while true; do
        print_header
        echo "   Task Status Manager"
        echo "   -------------------"
        # Expanded columns for Readability
        printf "   %-3s %-20s %-10s %-20s %-15s\n" "ID" "Task Name" "Status" "Human Time" "Cron Raw"
        echo "   ------------------------------------------------------------------------"

        for i in {1..5}; do
            local script="${SCRIPTS[$i]}"
            local name="${NAMES[$i]}"
            local is_root="true"
            [ "$script" == "update_pi_apps.sh" ] && is_root="false"

            local info; info=$(get_task_status "$script" "$is_root")
            local state; state=$(echo "$info" | cut -d'|' -f1)
            local sched; sched=$(echo "$info" | cut -d'|' -f2)
            
            local human_time; human_time=$(cron_to_human "$sched")
            
            printf "   %-3s %-20s %-10s %-20s %-15s\n" "$i" "$name" "$state" "$human_time" "$sched"
        done
        echo ""
        echo "   Enter ID to toggle/edit, or '0' to return to Main Menu."
        read -r -p "   Selection: " sel

        if [[ "$sel" == "0" ]]; then return; fi
        if [[ "$sel" =~ ^[1-5]$ ]]; then
            toggle_task "$sel"
        fi
    done
}

run_fresh_install() {
    print_header
    echo "Welcome to the One-Line Installer."
    echo "This wizard will set up your email and default schedules."
    echo ""
    check_dependencies
    configure_email_interactive
    download_scripts
    
    echo ""
    echo "Setting up default schedules..."
    echo "Select which tasks to enable. Press Enter to accept default [Y]."
    
    # Enable all by default for fresh install but allow opt-out
    for i in {1..5}; do
        local script="${SCRIPTS[$i]}"
        local name="${NAMES[$i]}"
        local sched="${DEFAULTS[$i]}"
        local human; human=$(cron_to_human "$sched")
        
        read -r -p "$i. Enable $name ($human)? [Y/n]: " choice
        choice=${choice:-Y}
        
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            # Determine root/user
            if [ "$script" == "update_pi_apps.sh" ]; then
                 (crontab -l 2>/dev/null | grep -v "$script"; echo "$sched $INSTALL_DIR/$script") | crontab -
            else
                 (sudo crontab -l 2>/dev/null | grep -v "$script"; echo "$sched $INSTALL_DIR/$script") | sudo crontab -
            fi
            echo "Enabled $name"
        else
            echo "Skipped $name"
        fi
    done
    
    echo ""
    echo "Installation Complete!"
    read -r -p "Press Enter to open the Manager Menu..."
    main_menu
}

main_menu() {
    while true; do
        print_header
        echo "   1. Configure Email Settings"
        echo "   2. View Current Email Config"
        echo "   3. Manage Tasks & Schedules (Enable/Disable)"
        echo "   4. Force Update Scripts (from GitHub)"
        echo "   5. Uninstall Suite"
        echo "   0. Exit"
        echo ""
        
        # Prevent infinite loops during automated testing if input stream runs dry
        if ! read -r -p "   Choose an option: " opt; then
            echo ""
            echo "EOF detected. Exiting."
            exit 0
        fi

        case $opt in
            1) configure_email_interactive ;;
            2) show_email_config ;;
            3) manage_tasks_ui ;;
            4) download_scripts ;;
            5) 
                read -r -p "Are you sure you want to uninstall? [y/N]: " un
                if [[ "$un" =~ ^[Yy]$ ]]; then
                    if [ -f "./uninstall.sh" ]; then
                        ./uninstall.sh
                    else
                        curl -sSL "$RAW_URL/uninstall.sh" | bash
                    fi
                    exit 0
                fi
                ;;
            0) exit 0 ;;
            *) echo "Invalid option." ;;
        esac
    done
}

# --- Entry Point ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]] && [ -z "$INSTALL_SH_SOURCED" ]; then
    # Check if already installed
    if [ -d "$INSTALL_DIR" ]; then
        main_menu
    else
        run_fresh_install
    fi
fi
