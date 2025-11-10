#!/bin/bash

CA_DIR=/opt/vast-ca
CA_CERT=root.cert.pem
CA_KEY=root.key.pem

if [ ! -d "$CA_DIR" ]; then
	echo "Certificate Authority path \"${CA_DIR}\" does not exist! check CA path!"
	exit 1
fi

if [ ! -f "${CA_DIR}/ca/${CA_CERT}" ] || [ ! -f "${CA_DIR}/ca/${CA_KEY}" ]; then
	echo "CA certificate and/or key not found in \"${CA_DIR}/ca\" - check CA path!"
	exit 1
fi

read -p 'user id: ' userid
read -p 'user name (full name): ' username
read -p 'country name (2 letter code): ' dn_C
read -p 'state or province name (full name): ' dn_ST
read -p 'locality name (eg, city): ' dn_L
read -p 'organization name (eg, company): ' dn_O
read -p 'certificate valid days [3650]: ' valid_days

echo

if [ -z "$userid" ]; then
	echo "userid is required! cannot continue"
	exit 1
fi

if [ -z "$username" ]; then
	echo "user full name is required! cannot continue"
	exit 1
fi

if [ -z "$dn_C" ]; then
	echo "country name is required! cannot continue"
	exit 1
fi

if [ -z "$dn_ST" ]; then
	echo "state/province name is required! cannot continue"
	exit 1
fi

if [ -z "$dn_L" ]; then
	echo "locality name is required! cannot continue"
	exit 1
fi

if [ -z "$dn_O" ]; then
	echo "organization name is required! cannot continue"
	exit 1
fi


output_dir=$(pwd)
if [ ! -z "$1" ]; then
	output_dir="$1"
fi

if [ -z "$valid_days" ]; then
	valid_days=3650
fi

dn_CN="$username $userid"

tmpfile=$(mktemp)

echo "[req]" >> $tmpfile
echo "distinguished_name = dn" >> $tmpfile
echo "prompt             = no" >> $tmpfile
echo "" >> $tmpfile
echo "[dn]" >> $tmpfile
echo "C=\"$dn_C\"" >> $tmpfile
echo "ST=\"$dn_ST\"" >> $tmpfile
echo "L=\"$dn_L\"" >> $tmpfile
echo "O=\"$dn_O\"" >> $tmpfile
echo "CN=\"$dn_CN\"" >> $tmpfile

#echo "$tmpfile"
#cat $tmpfile

#echo "openssl genrsa -out ${output_dir}/${userid}.key 2048"
#echo "openssl req -new -key ${output_dir}/${userid}.key -out ${output_dir}/${userid}.csr -config ${tmpfile}"
#echo "openssl x509 -req -in ${output_dir}/${userid}.csr -CA ${CA_DIR}/ca/${CA_CERT} -CAkey ${CA_DIR}/ca/${CA_KEY} -CAcreateserial -out ${output_dir}/${userid}.crt -days $valid_days -sha256"
#echo "openssl pkcs12 -export -clcerts -in ${output_dir}/${userid}.crt -inkey ${output_dir}/${userid}.key -out ${output_dir}/${userid}.p12"

openssl genrsa -out ${output_dir}/${userid}.key 2048
openssl req -new -key ${output_dir}/${userid}.key -out ${output_dir}/${userid}.csr -config ${tmpfile}
openssl x509 -req -in ${output_dir}/${userid}.csr -CA ${CA_DIR}/ca/${CA_CERT} -CAkey ${CA_DIR}/ca/${CA_KEY} -CAcreateserial -out ${output_dir}/${userid}.crt -days $valid_days -sha256
openssl pkcs12 -export -clcerts -in ${output_dir}/${userid}.crt -inkey ${output_dir}/${userid}.key -out ${output_dir}/${userid}.p12

rm $tmpfile




