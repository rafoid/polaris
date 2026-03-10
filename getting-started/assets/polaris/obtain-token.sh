#
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
#

set -e

apk add --no-cache jq

realm=${1:-"POLARIS"}

# Retry logic: try up to 30 times with 3 second delays
MAX_RETRIES=30
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  echo "Attempting to obtain access token (attempt $((RETRY_COUNT + 1))/$MAX_RETRIES)..."

  # Use --fail-with-body to get response even on HTTP errors, and capture exit code
  RESPONSE=$(curl -s --fail-with-body http://polaris:8181/api/catalog/v1/oauth/tokens \
    --user ${CLIENT_ID}:${CLIENT_SECRET} \
    -H "Polaris-Realm: $realm" \
    -d grant_type=client_credentials \
    -d scope=PRINCIPAL_ROLE:ALL 2>&1) || CURL_EXIT=$?

  # If curl succeeded (exit 0), try to extract token
  if [ -z "${CURL_EXIT}" ] || [ "${CURL_EXIT}" = "0" ]; then
    TOKEN=$(echo "$RESPONSE" | jq -r .access_token 2>/dev/null)

    if [ -n "${TOKEN}" ] && [ "${TOKEN}" != "null" ]; then
      echo "Successfully obtained access token."
      export TOKEN
      return 0
    fi
  fi

  RETRY_COUNT=$((RETRY_COUNT + 1))
  if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
    echo "Failed to obtain token (curl exit: ${CURL_EXIT:-0}), retrying in 3 seconds..."
    sleep 3
  fi
  unset CURL_EXIT
done

echo "Failed to obtain access token after $MAX_RETRIES attempts."
echo "Last response: $RESPONSE"
exit 1
