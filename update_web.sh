#!/bin/bash

# Must be run as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root"
    command="$0 $@"
    su -c "$command"
    exit 1
fi

script_path=$(realpath "$0")
base_path=$(dirname "$script_path")

# Task map
declare -A scripts=(
    [js]="minify_js.sh"
    [sass]="sass.sh"
    [blackphp]="blackphp_sync.sh"
    [mysqldump]="mysqldump.sh"
    [language]="language.sh"
    [images]="images.sh"
)

# Usage function
usage() {
    echo "Usage: blackphp-update [all|${!scripts[@]}]"
    echo "  all        Run all tasks"
    echo "  ${!scripts[@]}  Run specific task(s)"
    exit 1
}

# If no arguments, show usage
if [ $# -eq 0 ]; then
    usage
fi

# If "all" is provided, run all tasks
if [[ " $* " =~ " all " ]]; then
    echo "Running all tasks..."
    for key in "${!scripts[@]}"; do
        echo "Running: ${scripts[$key]}"
        "$base_path/${scripts[$key]}"
    done
else
    for task in "$@"; do
        if [[ ${scripts[$task]+_} ]]; then
            echo "Running: ${scripts[$task]}"
            "$base_path/${scripts[$task]}"
        else
            echo "Invalid task: $task"
            usage
        fi
    done
fi
