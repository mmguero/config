#!/bin/bash

# generate self-signed CA, server, and client .crt/.key files and dhparam.pem

# can test with:
#   openssl s_server -Verify 999 -CAfile ca.crt -key server.key -cert server.crt -accept 44330 -www
#   openssl s_client -CAfile ca.crt -key client.key -cert client.crt -showcerts -connect localhost:44330

set -e
set -u
set -o pipefail

ENCODING="utf-8"

RUN_PATH="$(pwd)"
OUTPUT_PATH="$(pwd)"/certs_$(date "+%Y-%m-%d_%H:%M:%S")

# create a temporary directory to store our results in (make sure /tmp is big enough to extract all of these logs into!)
WORKDIR="$(mktemp -d -t keygen-XXXXXX)"

# cleanup - on exit ensure the leftover files are shredded temporary directory is removed
function cleanup {
  popd >/dev/null 2>&1
  shred -u "$WORKDIR"/* >/dev/null 2>&1 || true
  if ! rm -rf "$WORKDIR"; then
    echo "Failed to remove temporary directory '$WORKDIR'" >&2
    exit 1
  fi
}

function randomStateAbbr {
  STATES=("AL" "AK" "AZ" "AR" "CA" "CO" "CT" "DE" "DC" "FL" "GA" "HI" "ID" "IL" "IN" "IA" "KS" "KY" "LA" "ME" "MD" "MA" "MI" "MN" "MS" "MO" "MT" "NE" "NV" "NH" "NJ" "NM" "NY" "NC" "ND" "OH" "OK" "OR" "PA" "RI" "SC" "SD" "TN" "TX" "UT" "VT" "VA" "WA" "WV" "WI" "WY")
  RANDOM=$$$(date +%s)
  CHOSEN_STATE=${STATES[$RANDOM % ${#STATES[@]}]}
  echo "$CHOSEN_STATE"
}

function randomStateFull {
  STATES=("Alabama" "Alaska" "Arizona" "Arkansas" "California" "Colorado" "Connecticut" "Delaware" "District of Columbia" "Florida" "Georgia" "Hawaii" "Idaho" "Illinois" "Indiana" "Iowa" "Kansas" "Kentucky" "Louisiana" "Maine" "Maryland" "Massachusetts" "Michigan" "Minnesota" "Mississippi" "Missouri" "Montana" "Nebraska" "Nevada" "New Hampshire" "New Jersey" "New Mexico" "New York" "North Carolina" "North Dakota" "Ohio" "Oklahoma" "Oregon" "Pennsylvania" "Rhode Island" "South Carolina" "South Dakota" "Tennessee" "Texas" "Utah" "Vermont" "Virginia" "Washington" "West Virginia" "Wisconsin" "Wyoming")
  RANDOM=$$$(date +%s)
  CHOSEN_STATE=${STATES[$RANDOM % ${#STATES[@]}]}
  echo "$CHOSEN_STATE"
}

if [ -d "$WORKDIR" ]; then
  # ensure that if we "grabbed a lock", we release it (works for clean exit, SIGTERM, and SIGINT/Ctrl-C)
  trap "cleanup" EXIT

  # chmod and chdir to the work directory
  chmod 700 "$WORKDIR"
  pushd "$WORKDIR" >/dev/null 2>&1

  # -----------------------------------------------
  # generate new ca/server/client certificates/keys

  # ca -------------------------------
  echo "Generating CA certificate and key..."

  SUBJECT_DEFAULT="/C=US/ST=$(randomStateAbbr)/O=ACME/OU=R&D"
  SUBJECT=""
  while [[ -z $SUBJECT ]]; do
    echo ""
    read -p "CA subject [$SUBJECT_DEFAULT]? " SUBJECT
    SUBJECT=${SUBJECT:-$SUBJECT_DEFAULT}
  done
  openssl genrsa -out ca.key 2048
  openssl req -x509 -new -nodes -key ca.key -sha256 -days 3650 -subj "$SUBJECT" -out ca.crt

  # server -------------------------------
  echo "Generating server certificate and key..."

  cat <<EOF > "server.conf"
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = yes

[req_distinguished_name]
countryName           = Country Name (2 letter code)
countryName_default   = US
countryName_min       = 2
countryName_max       = 2

stateOrProvinceName         = State or Province Name (full name)
stateOrProvinceName_default = $(randomStateFull)

localityName                = Locality Name (full name)

0.organizationName          = Organization Name (e.g., company)
0.organizationName_default  = ACME

organizationalUnitName         = Organizational Unit Name (e.g., section)
organizationalUnitName_default = R&D

commonName          = Common Name (e.g., your name or server hostname)
commonName_max      = 64

emailAddress        = Email Address
emailAddress_max    = 40

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
EOF

  openssl genrsa -out server.key 2048
  openssl req -sha512 -new -key server.key -out server.csr -config server.conf
  openssl x509 -days 3650 -req -sha512 -in server.csr -CAcreateserial -CA ca.crt -CAkey ca.key -out server.crt -extensions v3_req -extfile server.conf

  mv server.key server.key.pem
  openssl pkcs8 -in server.key.pem -topk8 -nocrypt -out server.key
  rm -f server.key.pem

  # client -------------------------------
  echo "Generating client certificate and key..."

  cat <<EOF > "client.conf"
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = yes

[req_distinguished_name]
countryName           = Country Name (2 letter code)
countryName_default   = US
countryName_min       = 2
countryName_max       = 2

stateOrProvinceName         = State or Province Name (full name)
stateOrProvinceName_default = $(randomStateFull)

localityName                = Locality Name (full name)

0.organizationName          = Organization Name (e.g., company)
0.organizationName_default  = ACME

organizationalUnitName         = Organizational Unit Name (e.g., section)
organizationalUnitName_default = R&D

commonName          = Common Name (e.g., your name or server hostname)
commonName_max      = 64

emailAddress        = Email Address
emailAddress_max    = 40

[usr_cert]
basicConstraints = CA:FALSE
nsCertType = client, server
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer:always
keyUsage = critical, digitalSignature, keyEncipherment, keyAgreement, nonRepudiation
extendedKeyUsage = serverAuth, clientAuth

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth, clientAuth
EOF

  openssl genrsa -out client.key 2048
  openssl req -sha512 -new -key client.key -out client.csr -config client.conf
  openssl x509 -days 3650 -req -sha512 -in client.csr -CAcreateserial -CA ca.crt -CAkey ca.key -out client.crt -extensions v3_req -extensions usr_cert -extfile client.conf
  # -----------------------------------------------

  # dhparam ------------------------------
  echo "Generating dhparam..."
  openssl dhparam -out dhparam.pem 2048
  # -----------------------------------------------

  mkdir -p "$OUTPUT_PATH"
  chmod 700 "$OUTPUT_PATH"
  rm -f *.conf *.csr *.srl
  cp ./* "$OUTPUT_PATH"/
fi
