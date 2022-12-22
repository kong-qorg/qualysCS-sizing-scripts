## Code here runs inside the initialize() function
## Use it for anything that you need to run before any other function, like
## setting environment variables:
## CONFIG_FILE=settings.ini
##
## Feel free to empty (but not delete) this file.
##########################################################################################
## Utility functions.
##########################################################################################
cecho () {
 
    declare -A colors;
    colors=(\
        ['black']='\E[0;47m'\
        ['red']='\E[0;31m'\
        ['green']='\E[0;32m'\
        ['yellow']='\E[0;33m'\
        ['blue']='\E[0;34m'\
        ['magenta']='\E[0;35m'\
        ['cyan']='\E[0;36m'\
        ['white']='\E[0;37m'\
    );
 
    local defaultMSG="No message passed.";
    local defaultColor="black";
    local defaultNewLine=true;
 
    while [[ $# -gt 1 ]];
    do
    key="$1";
 
    case $key in
        -c|--color)
            color="$2";
            shift;
        ;;
        -n|--noline)
            newLine=false;
        ;;
        *)
            # unknown option
        ;;
    esac
    shift;
    done
 
    message=${1:-$defaultMSG};   # Defaults to default message.
    color=${color:-$defaultColor};   # Defaults to default color, if not specified.
    newLine=${newLine:-$defaultNewLine};
 
    echo -en "${colors[$color]}";
    echo -en "$message";
    if [ "$newLine" = true ] ; then
        echo;
    fi
    tput sgr0; #  Reset text attributes to normal without clearing screen.
 
    return;
}

logErrorExit() {
  echo
  echo "ERROR: ${1}"
  #cecho -c 'red' "ERROR: $@";
  echo
  exit 1
}
debug () {
 
    cecho -c 'green' "$@";
    FilelogDebug
}
warning () {
 
    cecho -c 'yellow' "$@";
    Filelog
}
 
error () {
 
    cecho -c 'red' "$@";
    Filelog
}
 
info () {
 
    cecho -c 'blue' "$@";
    Filelog "INFO" "$@";
}

FilelogDebug() {
  # Set the message and optional log level
  local message=$1
  local level=${2:-DEBUG}

  # Set the log file location
  local log_file="./debug.log"
  #local log_file="/var/log/my-log.log"

  # Set the current time
  local time=$(date "+%Y-%m-%d %H:%M:%S")

  # Write the log message to the log file
  echo "$time [$level] $message" >> "$log_file"
}

Filelog() {
  # Set the log level and message
  local level=$1
  local message=$2

  # Set the log file location
  local log_file="./log.log"

  # Set the current time
  local time=$(date "+%Y-%m-%d %H:%M:%S")

  # Write the log message to the log file
  echo "$time [$level] $message" >> "$log_file"
}