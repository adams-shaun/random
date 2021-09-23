#!/usr/bin/env bash

set -xeuEo pipefail

mkdir -p ecc
cd ecc

openssl ecparam \
  -genkey \
  -name prime256v1 \
  -out key.pem

openssl req \
  -new \
  -sha256 \
  -key key.pem \
  -days 365 \
  -out csr.csr \
  -subj "/C=US/ST=Colorado/L=Longmont/O=Aspen Mesh/CN=''"

CONFIG="
[req]
distinguished_name=dn
[ dn ]
[ ext ]
basicConstraints=CA:TRUE,pathlen:0
"

openssl req \
  -config <(echo "$CONFIG") \
  -key key.pem \
  -in csr.csr \
  -x509 \
  -extensions ext \
  -keyout root-key.pem \
  -out root-cert.pem

cp root-cert.pem ca-cert.pem
cp key.pem root-key.pem
cp ca-cert.pem cert-chain.pem

tail +4 root-key.pem > ca-key.pem