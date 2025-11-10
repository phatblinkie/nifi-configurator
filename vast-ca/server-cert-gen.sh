#!/bin/bash

#CA_DIR=/opt/vast-ca
CA_DIR=/mission-share/vast-ca
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

read -p 'fully qualified domain name: ' fqdn

sanArray=($fqdn)
while IFS= read -r -p "additional name (empty line if none): " line; do
    [[ $line ]] || break  # break if line is empty
    sanArray+=("$line")
done

printf -v santemp 'DNS:%s,' "${sanArray[@]}"
san=${santemp::-1}
#echo "$san"


read -p 'country name (2 letter code): ' dn_C
read -p 'state or province name (full name): ' dn_ST
read -p 'locality name (eg, city): ' dn_L
read -p 'organization name (eg, company): ' dn_O
read -p 'certificate valid days [3650]: ' valid_days
echo
read -p 'key alias [silkwave]: ' key_alias

echo

if [ -z "$fqdn" ]; then
	echo "fqdn is required! cannot continue"
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

if [ -z "$key_alias" ]; then
        key_alias="silkwave"
fi


output_dir=$(pwd)
if [ ! -z "$1" ]; then
	output_dir="$1"
fi

if [ -z "$valid_days" ]; then
	valid_days=3650
fi

dn_CN="$fqdn"

tmpfile=$(mktemp)
tmpfile2=$(mktemp)

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
echo "" >> $tmpfile
echo "[SAN]" >> $tmpfile
#echo "subjectAltName=DNS:$dn_CN" >> $tmpfile
echo "subjectAltName=$san" >> $tmpfile

echo "[SAN]" >> $tmpfile2
#echo "subjectAltName=DNS:$dn_CN" >> $tmpfile2
echo "subjectAltName=$san" >> $tmpfile2


#echo "openssl genrsa -out ${output_dir}/${fqdn}.key 2048"
#echo "openssl req -new -key ${output_dir}/${fqdn}.key -out ${output_dir}/${fqdn}.csr -reqexts SAN -config ${tmpfile}"
#echo "openssl x509 -req -in ${output_dir}/${fqdn}.csr -CA ${CA_DIR}/ca/${CA_CERT} -CAkey ${CA_DIR}/ca/${CA_KEY} -CAcreateserial -extensions SAN -extfile ${tmpfile2} -out ${output_dir}/${fqdn}.crt -days $valid_days -sha256"
#echo "openssl pkcs12 -export -clcerts -in ${output_dir}/${fqdn}.crt -inkey ${output_dir}/${fqdn}.key -out ${output_dir}/${fqdn}.p12"

openssl genrsa -out ${output_dir}/${fqdn}.key 2048
openssl req -new -key ${output_dir}/${fqdn}.key -out ${output_dir}/${fqdn}.csr -reqexts SAN -extensions SAN -config ${tmpfile}
openssl x509 -req -in ${output_dir}/${fqdn}.csr -CA ${CA_DIR}/ca/${CA_CERT} -CAkey ${CA_DIR}/ca/${CA_KEY} -CAcreateserial -extensions SAN -extfile ${tmpfile2} -out ${output_dir}/${fqdn}.crt -days $valid_days -sha256
openssl pkcs12 -export -clcerts -in ${output_dir}/${fqdn}.crt -inkey ${output_dir}/${fqdn}.key -name ${key_alias} -out ${output_dir}/${fqdn}.p12

rm $tmpfile
rm $tmpfile2



