#!/bin/bash

PROTO='http'
PORT=80
JSON_PATH='health'
JSON_KEY='health'
JSON_EXPECTED_VALUE='true'

while getopts :sh:P:p:k:e: opt "$@"; do
  case $opt in
    s)
      PROTO='https'
      ;;
    h)
      HOST=$OPTARG
      ;;
    P)
      PORT=$OPTARG
      ;;
    p)
      JSON_PATH=$OPTARG
      ;;
    k)
      JSON_KEY=$OPTARG
      ;;
    e)
      JSON_EXPECTED_VALUE=$OPTARG
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done

URL="${PROTO}://${HOST}:${PORT}/${JSON_PATH}"
HTTPCODE=`curl --write-out %{http_code} --silent --output /dev/null $URL`

if [ ${HTTPCODE} -ne 200 ];then
  echo -e "HTTP_RESPONSE-CODE != 200"
  exit 1
fi

JSON_VALUE=`curl -s $URL| jq -r .${JSON_KEY}`
if [ ${JSON_VALUE} != ${JSON_EXPECTED_VALUE} ];then
  echo -e "Found JSON element value ${JSON_VALUE} does not match expected ${JSON_EXPECTED_VALUE}"
  exit 1
fi

echo -e "OK"

exit 0
