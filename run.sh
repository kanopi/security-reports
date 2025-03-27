#!/usr/bin/env bash

set -e
set -o pipefail

if [[ "${DEBUG}" != "" ]]; then
    set -x
fi

#### VARIABLES
# Console colors
green='\033[0;32;49m'
green_bg='\033[0;42;30m'
yellow='\033[0;33;49m'
yellow_bold='\033[1;33;49m'
yellow_bg='\033[0;43;30m'
red='\033[0;91;49m'
red_bg='\033[0;101;30m'
blue='\033[0;34;49m'
lime='\033[0;92;49m'
acqua='\033[0;96;49m'
magenta='\033[0;35;49m'
lightmagenta='\033[0;95;49m'
lightmagenta_bg='\033[0;105;30m'
NC='\033[0m'

if [[ -f .env ]]; then
  . ./.env
fi

# Configurable Variables
PASSWORD=${PASSWORD:-password}
USERNAME=${USERNAME:-admin}
PORT=${PORT:-9000}
HOST=${HOST:-"http://127.0.0.1:9000"}
MAX_TRIES=${MAX_TRIES:-3}
SLEEPTIME=${SLEEPTIME:-90}
PROJECT_DIRECTORY=${PROJECT_DIRECTORY:-$(pwd)}
PROJECT_NAME=${PROJECT_NAME:-$(basename ${PROJECT_DIRECTORY})}
SERVICE_NAME=${SERVICE_NAME:-sonarqube}

SONARQUBE_CLI_REMOTE_HOST=${SONARQUBE_CLI_REMOTE_HOST:-"http://${SERVICE_NAME}:9000"}
SONARQUBE_SERVICE_IMAGE=${SONARQUBE_SERVICE_IMAGE:-"sonarqube:9-community"}
SONARQUBE_REPORT_IMAGE=${SONARQUBE_REPORT_IMAGE:-"devkteam/sonarqube-report:latest"}
SONARQUBE_CLI_IMAGE=${SONARQUBE_CLI_IMAGE:-"devkteam/sonar-scanner-cli:latest"}
SONARQUBE_REPORT_FILE_NAME=${SONARQUBE_REPORT_FILE_NAME:-"report.pdf"}
CLEANUP=${CLEANUP}

DEFAULT_OPEN_REPORT=false

# Not Configurable
PROJECT_KEY=${PROJECT_KEY:-$(echo "${PROJECT_NAME}" | sed "s/[ |-]/_/g" | sed 's/[^a-zA-Z_]//g' | tr '[:upper:]' '[:lower:]')}
OLDPASS=admin
LOG_FILE=${LOG_FILE:-"/tmp/sonarqube.log"}
TRIES=0

# Find Version of Python
if [[ $(which python) ]]; then
  PYTHON=$(which python)
elif [[ $(which python3) ]]; then
  PYTHON=$(which python3)
fi

#### Helper Functions
echo-red ()      { echo -e "${red}$1${NC}"; }
echo-green ()    { echo -e "${green}$1${NC}"; }
echo-green-bg () { echo -e "${green_bg}$1${NC}"; }
echo-yellow ()   { echo -e "${yellow}$1${NC}"; }

echo-colored() {
    local bg_color=$1
    local text=$2
    local text_color=$3
    local output=$4
	echo -e "${bg_color} ${text} ${NC}\t${text_color}${output}${NC}";
	shift 4
	for arg in "$@"; do
		echo -e "           $arg"
	done
}

echo-warning() {
    echo-colored "${yellow_bg}" "WARNING" "${yellow}" "$@"
}

echo-error() {
    echo-colored "${red_bg}" "ERROR  " "${red}" "$@"
}

echo-notice() {
    echo-colored "${lightmagenta_bg}" "NOTICE " "${lightmagenta}" "$@"
}

echo-success() {
    echo-colored "${green_bg}" "SUCCESS" "${green}" "$@"
}

# print string in $1 for $2 times
echo-repeat() {
    seq  -f $1 -s '' $2; echo
}

# prints message to stderr
echo-stderr() {
	(>&2 echo "$@")
}

# Exits fin if previous command exited with non-zero code
if_failed() {
	if [ ! $? -eq 0 ]; then
		echo-red "$*"
		exit 1
	fi
}

# Like if_failed but with more strict error
if_failed_error() {
	if [ ! $? -eq 0 ]; then
		echo-error "$@"
		exit 1
	fi
}

default_usage() {
  cat <<- EOF
Run SonarQube reporting for the code.

Usage:
  $(basename $0) <options> <command>

Options:
  -c, --cleanup            Cleanup all the items after done running report.

  -d, --directory          Directory to run the report in.
                           (Default: ${PROJECT_DIRECTORY})

  -h, --host               Hostname to access SonarQube data.
                           (Default: ${HOST})

  -k, --project-key        Project Key
                           (Default: ${PROJECT_KEY})

  -m, --max-tries          Max number of tries to check for remote host.
                           (Default: ${MAX_TRIES})

  -p, --password           Set the password for connecting to the instance of SonarQube/SonarCloud
                           (Default: ${PASSWORD})

  -r, --project            Set the project name
                           (Default: ${PROJECT_NAME})

  -s, --cli-remote-host    Set the remote host to connect to for the cli
                           (Default: ${SONARQUBE_CLI_REMOTE_HOST})

  -t, --port               Port to access SonarQube endpoint.
                           (Default: ${PORT})

  -o, --open               Open report after running.
                           (Default: ${DEFAULT_OPEN_REPORT})

  -f, --file               Report file name.
                           (Default: ${SONARQUBE_REPORT_FILE_NAME})

  --help                   Open Help

Commands:
  cleanup              Cleanup and remove all standing Docker containers.

  run-report           Generate a report based on the latest scan from SonarQube.

  run-scanner          Run the SonarQube CLI Scanner on the current code base. This is
                       run in an isolated Docker container.

  new-project          Create a new project, run the scanner, and generate the report necessary
                       for the provided instance.

  run                  Start the process from the beginning
                       - Check if SonarQube Instance is running
                       - Pull the latest version of Docker Images
                       - Start SonarQube Service.
                       - Change the password for first setup
                       - Update the libraries for the instance
                       - Create project on the SonarQube instance
                       - Run the CLI scanner
                       - Generate report

EOF
}

# Parse Options
while getopts "ocd:f:h:l:m:p:r:s:u:-:" OPT; do
  # support long options: https://stackoverflow.com/a/28466267/519360
  if [ "$OPT" = "-" ]; then   # long option: reformulate OPT and OPTARG
    OPT="${OPTARG%%=*}"       # extract long option name
    OPTARG="${OPTARG#$OPT}"   # extract long option argument (may be empty)
    OPTARG="${OPTARG#=}"      # if long option argument, remove assigning `=`
  fi
  case $OPT in
    o|open)               DEFAULT_OPEN_REPORT=true;;
    c|cleanup)            CLEANUP="1";;
    d|directory)          PROJECT_DIRECTORY="${OPTARG}";;
    f|file)               SONARQUBE_REPORT_FILE_NAME="${OPTARG}";;
    h|host)               HOST="${OPTARG}";;
    k|project-key)        PROJECT_KEY=$(echo "${OPTARG}" | sed "s/[ |-]/_/g" | sed 's/[^a-zA-Z_]//g' | tr '[:upper:]' '[:lower:]');;
    l|log)                LOG_FILE="${OPTARG}";;
    m|max-tries)          MAX_TRIES="${OPTARG}";;
    p|password)           PASSWORD="${OPTARG}";;
    r|project)            PROJECT_NAME="${OPTARG}";;
    s|cli-remote-host)    SONARQUBE_CLI_REMOTE_HOST="${OPTARG}";;
    u|user)               USERNAME="${OPTARG}";;
    help)                 default_usage; exit 0;;
    ??* )                 echo-error "Illegal option --$OPT"; default_usage; exit 2 ;;  # bad long option
    ? )                   exit 2 ;;  # bad short option (error reported via getopts)
  esac
done
shift $((OPTIND-1)) # remove parsed options and args from $@ list

cleanup() {
    echo-warning "Removing services..."
    docker rm -f ${SERVICE_NAME} > /dev/null
}

start_sonarqube() {
    docker run -itd --rm \
        --name ${SERVICE_NAME} \
        -p ${PORT}:${PORT} \
        ${SONARQUBE_SERVICE_IMAGE} > /dev/null
}

sonarqube_running() {
    # shellcheck disable=SC2005
    echo "$(docker ps -a | grep "${SERVICE_NAME}" | wc -l | tr -d '[:blank:]')"
}

check_sonarqube_status() {
    # shellcheck disable=SC2005
    echo "$(curl -fsSL -u "${USERNAME}:${OLDPASS}" "${HOST}/api/system/status" | grep "UP" | wc -l | tr -d '[:blank:]')"
}

get_sonarqube_status() {
    echo $([[ "${1}" == 0 ]] && echo "Not Started" || echo "Started")
}

#### Execution

project_exists() {
    echo $(curl -fsSL -u "${USERNAME}:${PASSWORD}" "${HOST}/api/projects/search?projects=${1}" | ${PYTHON} -c 'import json,sys;obj=json.load(sys.stdin);print(obj["paging"]["total"])')
}

pull_latest_images() {
    echo-notice "Pulling latest version of images..."

    docker pull --quiet ${SONARQUBE_SERVICE_IMAGE} > /dev/null || true
    docker pull --quiet ${SONARQUBE_REPORT_IMAGE} > /dev/null || true
    docker pull --quiet ${SONARQUBE_CLI_IMAGE} > /dev/null || true
}

check_status() {
    echo-notice "Checking SonarQube Status..."

    IS_STARTED=$(sonarqube_running)

    if [[ "${IS_STARTED}" == "1" ]]; then
        echo-warning "SonarQube service already started. Remove other instance. (Y/N)?"
        read remove_service
        remove_service=$(echo "${remove_service}" | tr '[:lower:]' '[:upper:]' | tr -d '[:blank:]')
        if [[ "${remove_service}" == "Y" ]] || [[ "${remove_service}" == "YES" ]]; then
            cleanup
        else
            if_failed_error "Sonarcloud instance already started. Close other one before moving forward."
        fi
    fi
}

start_service() {
    echo-notice "Starting Sonarqube..."

    start_sonarqube

    echo-notice "Sleeping for ${SLEEPTIME} seconds to wait for service to start..."

    sleep ${SLEEPTIME}

    # Divide by half
    SLEEPTIME=$((SLEEPTIME/2))

    echo-notice "Getting service status..."

    # Get status from the service.
    RESPONSE=$(check_sonarqube_status)

    TRIES=$((TRIES + 1))

    echo-notice "Service status...$(get_sonarqube_status $RESPONSE)"

    # Check and see service is responding yet.
    while [[ "${RESPONSE}" != "1" ]] && [[ "${TRIES}" < "${MAX_TRIES}" ]]; do
        echo-notice "Not started yet. Sleeping for ${SLEEPTIME} seconds..."
        sleep ${SLEEPTIME}
        RESPONSE=$(check_sonarqube_status)
        echo-notice "Service status...$(get_sonarqube_status $RESPONSE)"
        TRIES=$((TRIES + 1))
    done

    if [[ "${RESPONSE}" != "1" ]]; then
        if_failed_error "Service not properly starting. Exiting."
    fi

    echo-notice "Service started..."
}

change_password() {
    echo-notice "Changing initial default password..."

    curl -fsSL -u ${USERNAME}:${OLDPASS} \
        ${HOST}/api/users/change_password \
        -d "login=${USERNAME}" \
        -d "password=${PASSWORD}" \
        -d "previousPassword=${OLDPASS}" >/dev/null
}

update_libraries() {
    echo-notice "Adding extensions to PHP Library..."

    curl -fsSL -u ${USERNAME}:${PASSWORD} \
        ${HOST}/api/settings/set \
        -d 'key=sonar.php.file.suffixes' \
        -d 'values=php&values=php3&values=php4&values=php5&values=phtml&values=inc&values=module' > /dev/null
}

delete_project() {
    echo-notice "Deleting Project: ${1}..."
    curl -fsSL -u ${USERNAME}:${PASSWORD} \
        ${HOST}/api/projects/delete \
        -d "project=${1}"
}

create_project() {
    PROJECT_EXISTS=$(project_exists ${PROJECT_KEY})
    if [[ "${PROJECT_EXISTS}" != "0" ]]; then
        delete_project ${PROJECT_KEY}
    fi

    echo-notice "Creating Project..."

    curl -fsSL -u ${USERNAME}:${PASSWORD} \
        ${HOST}/api/projects/create \
        -d "name=${PROJECT_NAME}" \
        -d "project=${PROJECT_KEY}" > /dev/null
}

run_scanner() {
    # Create The Volume
    local VOLUME_NAME="scanner_${PROJECT_KEY}"
    echo-notice "Deleting Older Volume ${VOLUME_NAME}..."
    docker volume rm -f "${VOLUME_NAME}" >/dev/null 2>/dev/null || true
    echo-notice "Creating Project Volume..."
    docker volume create "${VOLUME_NAME}" >/dev/null

    # Copy the Contents
    echo-notice "Copying Project to Volume..."
    docker rm -f "temp_${PROJECT_NAME}" 2>/dev/null || true
    docker run --quiet -d --rm -it \
        -v "${VOLUME_NAME}:/project" \
        --name="temp_${PROJECT_NAME}" \
        busybox > /dev/null
    docker cp ${PROJECT_DIRECTORY} "temp_${PROJECT_NAME}":/project > /dev/null
    docker rm -f "temp_${PROJECT_NAME}" >/dev/null

    echo-notice "Removing unresolved symlinks (which can cause the scanner to fail)..."
    docker run --rm -it -v "${VOLUME_NAME}:/project" \
        alpine find project/${PROJECT_NAME} -type l -exec test ! -e {} \; -print -delete

    # Run the Scanner
    echo-notice "Running Scanner..."
    echo-warning "This process can take a decent amount of time..."
    docker run --rm -it -v "${VOLUME_NAME}:/usr/src" \
        --link ${SERVICE_NAME} \
        ${SONARQUBE_CLI_IMAGE} \
        sonar-scanner \
        -Dsonar.projectKey=${PROJECT_KEY} \
        -Dsonar.sources=. \
        -Dsonar.host.url=${SONARQUBE_CLI_REMOTE_HOST} \
        -Dsonar.login="${USERNAME}" \
        -Dsonar.password="${PASSWORD}" > ${LOG_FILE}

    # Remove volume
    docker volume rm -f "${VOLUME_NAME}" >/dev/null 2>/dev/null || true
}

validate_report() {
    echo-notice "Confirming Report Exists"
    if [ ! -f "${PROJECT_DIRECTORY}/${SONARQUBE_REPORT_FILE_NAME}" ]; then
        echo-error "${SONARQUBE_REPORT_FILE_NAME} not found"
    else
        echo-success "${SONARQUBE_REPORT_FILE_NAME} found"
        ask_open_report
    fi
}

# Open the report
open_report () {
    if [ "$(which open)" != "" ]; then
        open "${PROJECT_DIRECTORY}/${SONARQUBE_REPORT_FILE_NAME}"
    fi
}

# Ask if the person would like to open the report
ask_open_report() {
    if [ ! $DEFAULT_OPEN_REPORT ]; then
        echo-warning "Open Report? (Y/N)"
        read open_report
        local open_report=$(echo "${open_report}" | tr '[:lower:]' '[:upper:]' | tr -d '[:blank:]')
        if [[ "${open_report}" == "Y" ]] || [[ "${open_report}" == "YES" ]]; then
            open_report
        fi
    else
        open_report
    fi
}

run_report() {
    echo-notice "Generating Report..."

    if [[ "${BUILD_REPORT_IMAGE}" == "1" ]]; then
        CUSTOM_BUILD_IMAGE=${CUSTOM_BUILD_IMAGE:-"security_report_image"};
        if [[ -f "${BUILD_REPORT_DIRECTORY:-.}/Dockerfile" ]]; then
            echo-notice "Building Docker Image..."
            docker build -q -t "${CUSTOM_BUILD_IMAGE}" ${BUILD_REPORT_DIRECTORY:-.} > /dev/null
            SONARQUBE_REPORT_IMAGE="${CUSTOM_BUILD_IMAGE}"
        fi
    fi

    docker run --rm -it -v ${PROJECT_DIRECTORY}:/mnt/reports \
        --link ${SERVICE_NAME} \
        -e SONARQUBE_HOST=${SONARQUBE_CLI_REMOTE_HOST} \
        -e SONARQUBE_USER="${USERNAME}" \
        -e SONARQUBE_PASS="${PASSWORD}" \
        -e SONARQUBE_PROJECTS="${PROJECT_KEY}" \
        -e SONARQUBE_REPORT_FILE="${SONARQUBE_REPORT_FILE_NAME}" \
        ${SONARQUBE_REPORT_IMAGE}

    validate_report
}

check_requirements() {
  $(which docker > /dev/null) || if_failed_error "Docker Binary not found"
  $(docker ps > /dev/null) || if_failed_error "Docker not running"
}

check_requirements

# Execute subcommands
case "$1" in
    # Individual Commands
    run-scanner)
        run_scanner
        ;;
    run-report)
        run_report
        ;;
    cleanup)
        cleanup
        ;;
    # Compound Commands
    new-project)
        create_project
        run_scanner
        run_report
        ;;
    run-current)
        update_libraries
        create_project
        run_scanner
        run_report

        if [[ "${CLEANUP}" != "" ]]; then
            cleanup
        fi

        echo-green-bg " Completed "
        ;;
    start)
        check_status
        pull_latest_images
        start_service
        ;;
    run)
        check_status
        pull_latest_images
        start_service
        change_password
        update_libraries
        create_project
        run_scanner
        run_report

        if [[ "${CLEANUP}" != "" ]]; then
            cleanup
        fi

        echo-green-bg " Completed "
        ;;
    help)
        default_usage
        ;;
    *)
        default_usage
        echo-error "Command: ${1} not supported"
        exit 1
        ;;
esac
