#!/bin/bash

# stop nginx if it is running
# to extract backup data and be
# visible on the next nginx startup
service nginx stop

# print required variables for this script execution
echo "CERT_DOMAIN=$CERT_DOMAIN | CERT_EMAIL=$CERT_EMAIL | CERT_BUCKET=$CERT_BUCKET"

# write cert files to var making commands shorter
HASH=$(echo -n "$CERT_DOMAIN" | md5sum | cut -d ' ' -f 1)
CERTZIP="$HASH.zip"
CERTZIP_PATH=/etc/letsencrypt
CERTLIVE_PATH=$CERTZIP_PATH/live/$CERT_DOMAIN
CERTARCHIVE_PATH=$CERTZIP_PATH/archive/$CERT_DOMAIN
FULLCHAIN_PATH=$CERTZIP_PATH/live/$CERT_DOMAIN/fullchain.pem
PRIVKEY_PATH=$CERTZIP_PATH/live/$CERT_DOMAIN/privkey.pem

# check if exists some certbot backed up on aws s3
if [ -e $CERTZIP_PATH ]; then rm -rf $CERTZIP_PATH; fi
if [ -f $CERTZIP ]; then rm -f $CERTZIP; fi
aws s3 cp s3://$CERT_BUCKET/$CERTZIP /$CERTZIP 2> /dev/null

# extract zip if it was downloaded from aws s3
if [ -f $CERTZIP ]; then 
    unzip -o $CERTZIP -d .
    # remove non symlinked certificates
    rm -f $CERTLIVE_PATH/cert.pem
    rm -f $CERTLIVE_PATH/chain.pem
    rm -f $CERTLIVE_PATH/fullchain.pem
    rm -f $CERTLIVE_PATH/privkey.pem
    # symlink certifates (important to certbot handle certs)
    ln -s $CERTARCHIVE_PATH/cert1.pem $CERTLIVE_PATH/cert.pem
    ln -s $CERTARCHIVE_PATH/chain1.pem $CERTLIVE_PATH/chain.pem
    ln -s $CERTARCHIVE_PATH/fullchain1.pem $CERTLIVE_PATH/fullchain.pem
    ln -s $CERTARCHIVE_PATH/privkey1.pem $CERTLIVE_PATH/privkey.pem
fi

# write custom nginx conf for provided domain
nginx_config=$(cat <<EOF
    server {
        listen 80 default_server;
        listen [::]:80 default_server;
        root /var/www/html;
        server_name $CERT_DOMAIN;

        location / {
            proxy_pass http://app:80/;
            proxy_set_header Host \$http_host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }
    }
EOF
)
echo "$nginx_config" > /etc/nginx/conf.d/$CERT_DOMAIN.conf

# Start Nginx in the background
nginx -g "daemon off;" &
# Wait for Nginx to start
until nginx -t &> /dev/null
do
    echo "Waiting for Nginx to start..."
    sleep 1
done

# print step
echo "Nginx has started, handling certificate..."


# Use 'until' to continuously check for the desired response code
until [ "$(curl -s -o /dev/null -w "%{http_code}" "http://$CERT_DOMAIN")" -eq "200" ]; do
    echo "Waiting for $domain to respond with 200 OK"
    sleep 5  # Adjust the sleep duration as needed
done


# run certbot and issue a new challange if does not exists a cert or it is close expire
if (certbot --nginx --debug --non-interactive --agree-tos -m $CERT_EMAIL -d $CERT_DOMAIN) then
    echo "Certbot configured successfully..."

    # zip letsencrypt folder and copy to aws s3
    if [ -f $CERTZIP ]; then rm -f $CERTZIP; fi
    zip -r $CERTZIP $CERTZIP_PATH /etc/nginx/conf.d /etc/nginx/mime.types /etc/nginx/nginx.conf /etc/cron.d/certbot

    # upload cert zip to aws s3
    aws s3 cp $CERTZIP s3://$CERT_BUCKET/$CERTZIP;

else
    echo "Error on configure certbot..."
fi

wait