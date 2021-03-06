#!/bin/bash -e

export COMPONENT="db"
export API_IMAGE="$PRIVATE_IMAGE_REGISTRY/api:$RELEASE"
export LOGS_FILE="$RUNTIME_DIR/logs/$COMPONENT.log"

## Write logs of this script to component specific file
exec &> >(tee -a "$LOGS_FILE")

__validate_api_envs() {
  __process_msg "Initializing api environment variables"
  __process_msg "CONFIG_DIR: $CONFIG_DIR"
  __process_msg "RELEASE: $RELEASE"
  __process_msg "API_IMAGE: $API_IMAGE"
  __process_msg "DBNAME: $DBNAME"
  __process_msg "DBUSERNAME: $DBUSERNAME"
  __process_msg "DBPASSWORD: $DBPASSWORD"
  __process_msg "DBHOST: $DBHOST"
  __process_msg "DBPORT: $DBPORT"
  __process_msg "DBDIALECT: $DBDIALECT"
  __process_msg "LOGS_FILE: $LOGS_FILE"
  if [ "$ACCESS_KEY" == "" ]; then
    __process_error "Access key not present, exiting"
    exit 1
  else
    __process_msg "ACCESS_KEY: $ACCESS_KEY"
  fi

  if [ "$SECRET_KEY" == "" ]; then
    __process_error "Secret key not present, exiting"
    exit 1
  else
    __process_msg "SECRET_KEY: $SECRET_KEY"
  fi
}

__docker_login() {
  __process_msg "Updating docker credentials to pull Shippable images"

  local credentials_template="$SCRIPTS_DIR/configs/credentials.template"
  local credentials_file="/tmp/credentials"

  sed "s#{{ACCESS_KEY}}#$ACCESS_KEY#g" $credentials_template > $credentials_file
  sed -i "s#{{SECRET_KEY}}#$SECRET_KEY#g" $credentials_file

  mkdir -p ~/.aws
  mv -v $credentials_file ~/.aws
  local docker_login_cmd=$(aws ecr --region us-east-1 get-login)
  __process_msg "Docker login generated, logging into ecr"
  eval "$docker_login_cmd"
}

__run_api() {
  __process_msg "Running api container"

  local run_cmd="sudo docker run \
    -d \
    -e DBNAME=$DBNAME \
    -e DBUSERNAME=$DBUSERNAME \
    -e DBPASSWORD=$DBPASSWORD \
    -e DBHOST=$DBHOST \
    -e DBPORT=$DBPORT \
    -e DBDIALECT=$DBDIALECT \
    --net=host \
    --privileged=true \
    --name=fakeapi \
    $API_IMAGE
  "

  eval "$run_cmd"
  __process_msg "API container started"
}

__check_api() {
  __process_msg "Checking API container status"

  local interval=3
  local timeout=180
  local counter=0
  local is_booted=false

  while [ $is_booted != true ] && [ $counter -lt $timeout ]; do
    local running_api_container=$(sudo docker ps | \
      grep fakeapi | awk '{print $1}')

    if [ "$running_api_container" != "" ]; then
      __process_msg "Waiting fifteen seconds before stopping API container"
      is_booted=true
      sleep 15

      # Check if it's still running
      local api_container=$(sudo docker ps | grep fakeapi | awk '{print $1}')

      if [ "$api_container" != "" ]; then
        __process_msg "Stopping API container"
        sudo docker stop -t=0 $api_container
      fi

      sudo docker rm $running_api_container
    else
      local exited_api_container=$(sudo docker ps -a --filter status=exited | \
        grep fakeapi | awk '{print $1}')

      if [ "$exited_api_container" != "" ]; then
        __process_msg "Removing API container"
        sudo docker rm $exited_api_container
        is_booted=true
      else
        let "counter = $counter + $interval"
        sleep $interval
      fi
    fi
  done

  if [ $is_booted = false ]; then
    __process_error "Failed to boot api container"
    exit 1
  fi
}

main() {
  __process_marker "Booting fake api to generate models"

  __validate_api_envs
  __docker_login
  __run_api
  __check_api

  __process_msg "Started API container successfully"
}

main
