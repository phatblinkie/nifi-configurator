ca_2022.zip file
----------------

./ca
	the new VaST Certificate Authority files. This will replace the VaST CA already on a server.
        put this directory (and all its contents) in /opt/vast-ca (so there is a /opt/vast-ca/ca directory).
	if user client certificates were issued under the old CA, they must be re-generated with the new one.

./nginx/certs/*
	new files to replace files of the same name in /usr/local/nginx/certs and /usr/local/nginx/certs/crl.
	stop nginx before replacing the files "sudo service nginx stop".
	restart nginx afterwards "sudo service nginx start".

vast-admin-2022.p12
	client certificate signed by the new authority. install in browser to allow access to FUSE. password is "password"

cert-gen.sh
	script that uses the CA (above) to generate client certs for users to add to their web browsers. run
        it and it will prompt for the necessary information.

		
