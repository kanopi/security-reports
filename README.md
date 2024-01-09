# Security Report Generator

## SonarQube Report Generator

The following uses the SonarQube API to build an exportable report based on 
the items that are found within the scan. This works for both hosted solution 
and a local copy.

### Requirements

Docker is the only tool that is needed for this to run.

### Generating Report

#### Using the Docker Image

Running the docker image can be as simple as running the following:

```shell
docker -it --rm \
  -v $(pwd):/mnt/reports \
  -e SONARQUBE_HOST="https://sonarcloud.io" \
  -e SONARQUBE_USER="user" \
  -e SONARQUBE_PASS="abc" \
  -e SONARQUBE_PROJECTS="project_test" \
  devkteam/sonarqube-report:latest
```

##### Environment Variables

Environment variables can be used by either exporting them, or by using a `.env` file.

| Variable                  | Default                              | Description                                                                                           |
|---------------------------|--------------------------------------|-------------------------------------------------------------------------------------------------------|
| USERNAME                  | admin                                | Username used for logging into SonarQube Service                                                      |
| PASSWORD                  | password                             | Password used for logging into SonarQube Service                                                      |
| HOST                      | http://127.0.0.1:9000                | Hostname to communicate with SonarQube from the host machine                                          |
| SERVICE_NAME              | sonarqube                            | When setting up locally what is the name of the service/container to use.                             |
| MAX_TRIES                 | 3                                    | How many attempts should be made before everything fails                                              |
| SLEEPTIME                 | 90                                   | How long should the requests wait before they check again.<br>Used when setting up SonarQube locally. |
| SONARQUBE_SERVICE_IMAGE   | sonarqube:9-community                | SonarQube Docker image to use for local setup                                                         |
| PROJECT_DIRECTORY         | (current directory)                  | Location to run the scan from                                                                         |
| PROJECT_NAME              | (current directory)                  | Name of the project to create in SonarQube service                                                    |
| PROJECT_KEY               | (uses project name)                  | Project key within SonarQube service to pull data for                                                 |
| SONARQUBE_CLI_REMOTE_HOST | http://sonarqube:9000                | Remote host to use for sending code scan                                                              |
| SONARQUBE_CLI_IMAGE       | sonarsource/sonar-scanner-cli:latest | Image name to use for running                                                                         |
| SONARQUBE_REPORT_IMAGE    | devkteam/sonarqube-report:latest     | Docker image name to use for generating the report                                                    |
| CLEANUP                   | (blank)                              | If set will delete and remove all services after running                                              |
| LOG_FILE                  | /tmp/sonarqube.log                   | Where should all output be sent to for reviewing                                                      |
| SONARQUBE_EXTRA_PARAMS    | (blank)                              | JSON Structure where key is the endpoint. Additionally key 'global' is used for all requests.         |

#### Using PHP Source

Clone the source code

```shell
git clone git@github.com:kanopi/sonarqube-report sonarqube-report
cd sonarqube-report
```

Run Composer Install

```shell
composer install
```

Create the `.env` file. Use this to modify any environment variables that should
point to your SonarQube instance.

```shell
cp .env.dist .env
```

Run the `run.php` script

```shell
./run.php
```

### Building From Source

To build the image from source.

```shell
make build
```

### Running full process

Included as part of this is the full process of setting up a local instance of SonarQube and running the scanner on the 
current codebase.

```shell
bash <(curl -fsSL https://raw.githubusercontent.com/kanopi/security-reports/main/run.sh) run
```

## Pantheon Log Report Generator

The following generates a report using GoAccess. The following will generate an HTML report.

### Requirements

Docker is the only tool that is needed for this to run.

### Running full process

```shell
SITE_UUID=1a5b3e19-01af-4f19-ad34-abe5489370d0 bash <(curl -fsSL https://raw.githubusercontent.com/kanopi/security-reports/main/collect-logs.sh)
```
