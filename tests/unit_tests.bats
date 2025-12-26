#!/usr/bin/env bats

setup() {
    # Source the actual script logic
    # We use shebang guards to make this safe
    source ./install.sh
}

@test "Unit: Install - Arrays Initialized Correctly" {
    # Source again to ensure arrays are visible (setup's declare -A limits scope)
    source ./install.sh

    # Verify SCRIPTS array
    [ "${SCRIPTS[1]}" = "update_pi_os.sh" ]
    [ "${SCRIPTS[5]}" = "update_pi_apps.sh" ]
    
    # Verify NAMES array
    [ "${NAMES[1]}" = "System OS Update" ]
    
    # Verify DEFAULTS array
    [ "${DEFAULTS[1]}" = "0 3 * * 0" ]
    [ "${DEFAULTS[2]}" = "0 2 * * 0" ]
}

@test "Unit: Cron to Human - Daily" {
    run cron_to_human "0 0 * * *"
    [ "$output" = "Daily @ 00:00" ]
}

@test "Unit: Cron to Human - Weekly (All Days)" {
    # Test all branches of the case statement
    run cron_to_human "0 0 * * 0"
    [[ "$output" == "Weekly Sun @ 00:00" ]]

    run cron_to_human "0 0 * * 1"
    [[ "$output" == "Weekly Mon @ 00:00" ]]

    run cron_to_human "0 0 * * 2"
    [[ "$output" == "Weekly Tue @ 00:00" ]]

    run cron_to_human "0 0 * * 3"
    [[ "$output" == "Weekly Wed @ 00:00" ]]

    run cron_to_human "0 0 * * 4"
    [[ "$output" == "Weekly Thu @ 00:00" ]]

    run cron_to_human "0 0 * * 5"
    [[ "$output" == "Weekly Fri @ 00:00" ]]

    run cron_to_human "0 0 * * 6"
    [[ "$output" == "Weekly Sat @ 00:00" ]]

    run cron_to_human "0 0 * * 7"
    [[ "$output" == "Weekly Sun @ 00:00" ]]
}

@test "Unit: Cron to Human - Monthly" {
    run cron_to_human "0 0 1 * *"
    [[ "$output" == "Monthly 1 @ 00:00" ]]
    
    run cron_to_human "30 14 15 * *"
    [[ "$output" == "Monthly 15 @ 14:30" ]]
}

@test "Unit: Cron to Human - Padding Logic" {
    run cron_to_human "5 9 * * *"
    [[ "$output" =~ "Daily @ 09:05" ]]
}

@test "Unit: Cron to Human - Custom" {
    # Provide a cron with a specific month to ensure it triggers 'else' -> "Custom Schedule"
    run cron_to_human "0 0 * 1 *"
    [ "$output" = "Custom Schedule" ]
}

@test "Unit: Cron to Human - Invalid/Empty" {
    run cron_to_human ""
    [ "$output" = "-" ]
    
    run cron_to_human "-"
    [ "$output" = "-" ]
}

@test "Unit: Regex - ANSI Color Stripping" {
    # Simulate the sed command used in update_pi_apps.sh
    # Input has Color codes [96m and Title codes ]0;
    input_text=$(echo -e "\x1B[96mChecking apps...\x1B[0m\x1B]0;Title\x07Done")
    
    run bash -c "echo '$input_text' | sed -r 's/\x1B\[[0-9;]*[a-zA-Z]//g' | sed -r 's/\x1B\]0;[^\x07]*\x07//g'"
    
    [ "$status" -eq 0 ]
    [ "$output" = "Checking apps...Done" ]
}