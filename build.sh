#!/bin/bash
# Parameters
domain=(mydomain.com)
email="email@mydomain.com" # Adding a valid address is strongly recommended
rsa_key_size=4096
data_path="./data/certbot"
staging=0 # Set to 1 if you're testing your setup to avoid hitting request limits

# Check docker-compose
if ! [ -x "$(command -v docker-compose)" ]; then
  echo 'Error: docker-compose is not installed.' >&2
  exit 1
fi

# Check directories
if [ ! -d "$data_path" ]; then
  echo "### Creating necessary directories ... "
  mkdir -p "$data_path"
  mkdir -p "$data_path/www"
  mkdir -p "$data_path/conf"
  echo
fi

# Check certificate for domain
if [ -d "$data_path/conf/live/$domain" ]; then
  read -p "Existing data found for $domain. Continue and replace existing certificate? (y/N) " decision
  if [ "$decision" != "Y" ] && [ "$decision" != "y" ]; then
    exit
  fi
fi

# Download TLS parameters
if [ ! -e "$data_path/conf/options-ssl-nginx.conf" ] || [ ! -e "$data_path/conf/ssl-dhparams.pem" ]; then
  echo "### Downloading recommended TLS parameters ..."
  mkdir -p "$data_path/conf"
  curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf > "$data_path/conf/options-ssl-nginx.conf"
  curl -s https://raw.githubusercontent.com/certbot/certbot/master/certbot/certbot/ssl-dhparams.pem > "$data_path/conf/ssl-dhparams.pem"
  echo
fi

# Create dummy certificate
echo "### Creating dummy certificate for $domain ..."
path="/etc/letsencrypt/live/$domain"
mkdir -p "$data_path/conf/live/$domain"
docker-compose run --rm --entrypoint "\
 openssl req -x509 -nodes -newkey rsa:$rsa_key_size -days 1\
    -keyout '$path/privkey.pem' \
    -out '$path/fullchain.pem' \
    -subj '/CN=localhost'" certbot
echo

# Start nginx
echo "### Starting nginx ..."
docker-compose up --force-recreate -d nginx
echo

# Remove dummy certificate
echo "### Deleting dummy certificate for $domain ..."
docker-compose run --rm --entrypoint "\
  rm -Rf /etc/letsencrypt/live/$domain && \
  rm -Rf /etc/letsencrypt/archive/$domain && \
  rm -Rf /etc/letsencrypt/renewal/$domain.conf" certbot
echo

# Request a valid certificate for domain
echo "### Requesting Let's Encrypt certificate for $domain ..."
#Join $domain to -d args
domain_args=""
#for domain in "${domains[@]}"; do
  domain_args="$domain_args -d $domain"
#done

# Select appropriate email arg
case "$email" in
  "") email_arg="--register-unsafely-without-email" ;;
  *) email_arg="--email $email" ;;
esac

# Enable staging mode if needed
if [ $staging != "0" ]; then staging_arg="--staging"; fi

# Run certbot
docker-compose run --rm --entrypoint "\
  certbot certonly --webroot -w /var/www/certbot \
    $staging_arg \
    $email_arg \
    $domain_args \
    --rsa-key-size $rsa_key_size \
    --agree-tos \
    --force-renewal" certbot
echo

# Reload nginx
echo "### Reloading nginx ..."
docker-compose exec nginx nginx -s reload

# Docker compose
docker-compose up -d
