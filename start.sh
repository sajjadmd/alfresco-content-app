#!/usr/bin/env bash

show_help() {
  echo "Usage: ./start.sh"
  echo ""
  echo "-k or --keycloak if you want to use keycloak as identity provider"
  echo "-d or --down delete all container"
  echo "-wp or --windows-path convert to Windows path"
  echo "-hi or --host-ip set the host ip"
  echo "-hp or --host-port set the host port. Default 8080"
  echo "-w or --wait wait for backend. Default true"
  echo "-aca. Only redeploy ACA and skip the other docker compose services"
  echo "-h or --help"
}

set_keycloak(){
  KEYCLOAK="true"
}

set_windows_path(){
  export COMPOSE_CONVERT_WINDOWS_PATHS=1
}

down(){
  docker-compose down
  exit 0
}

set_host_ip(){
  SET_HOST_IP=$1
}

set_host_port(){
  HOST_PORT=$1
}

set_wait(){
  WAIT=$1
}

redeploy_aca(){
  REDEPLOY_ACA="true"
}

# Defaults
WAIT="true"
SET_HOST_IP=""
HOST_PORT="8080"
KEYCLOAK="false"
AIMS_PROPS=""
REDEPLOY_ACA="false"

while [[ $1 == -* ]]; do
  case "$1" in
    -h|--help|-\?) show_help; exit 0;;
    -k|--keycloak)  set_keycloak; shift;;
    -wp|--windows-path)  set_windows_path; shift;;
    -d|--down)  down; shift;;
    -aca)  redeploy_aca; shift;;
    -w|--wait)  set_wait $2; shift 2;;
    -hi|--host-ip)  set_host_ip $2; shift 2;;
    -hp|--host-port)  set_host_port $2; shift 2;;
    -*) echo "invalid option: $1" 1>&2; show_help; exit 1;;
  esac
done

if [ -n "${SET_HOST_IP}" ];then
  export HOST_IP=${SET_HOST_IP}
else
  echo "No HOST_IP set, try to figure out on its own ..."
  export HOST_IP=$(ifconfig | grep -E "([0-9]{1,3}\.){3}[0-9]{1,3}" | grep -v 127.0.0.1 | awk '{ print $2 }' | cut -f2 -d: | head -n1)
fi
echo "HOST_IP: ${HOST_IP}"

URL_FRAGMENT="content-app"
export APP_URL="http://${HOST_IP}:${HOST_PORT}/${URL_FRAGMENT}"
echo "Content Workspace: ${APP_URL}"

if [[ $KEYCLOAK == "true" ]]; then
  export APP_CONFIG_AUTH_TYPE="OAUTH"
  export APP_CONFIG_OAUTH2_HOST="http://${HOST_IP}:8085/auth/realms/alfresco"
  echo "Realm: ${APP_CONFIG_OAUTH2_HOST}"
  export APP_CONFIG_OAUTH2_CLIENTID="alfresco"
  export APP_CONFIG_OAUTH2_IMPLICIT_FLOW=true
  export APP_CONFIG_OAUTH2_SILENT_LOGIN=true
  export APP_CONFIG_OAUTH2_REDIRECT_SILENT_IFRAME_URI="${APP_URL}/assets/silent-refresh.html"
  export APP_CONFIG_OAUTH2_REDIRECT_LOGIN="${APP_URL}/"
  export APP_CONFIG_OAUTH2_REDIRECT_LOGOUT="/$URL_FRAGMENT/logout"
  # export APP_BASE_SHARE_URL="${APP_URL}#/preview/s"

  AIMS_PROPS="-Dauthentication.chain=identity-service1:identity-service,alfrescoNtlm1:alfrescoNtlm"
fi

export AIMS_PROPS=${AIMS_PROPS}

if [[ $REDEPLOY_ACA == "true" ]]; then
  echo "Redeploy content-app"
  docker-compose up --detach --build content-app
else
  echo "Start docker compose"
  docker-compose up -d --build
fi

if [[ $WAIT == "true" ]]; then
  echo "http://${HOST_IP:-localhost}:${HOST_PORT:-8080}/$URL_FRAGMENT/"
  echo "Waiting for the app ..."
  HOST_IP=$HOST_IP HOST_PORT=$HOST_PORT npm run wait:app
  if [ $? == 1 ]; then
    echo "Waiting failed -> exit 1"
    exit 1
  fi
fi
