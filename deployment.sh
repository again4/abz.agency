#!/bin/bash
apt update -y

apt install php-fpm php-cli php-mysql php-gd php-curl php-mbstring php-zip php-opcache php-xml php-mysqli -y

systemctl restart php8.3-fpm

apt install nginx -y

apt install redis-tools

read -p "Enter your Domain Name: " DOMAIN_NAME

# Запитуємо користувача про дані для бази даних
read -p "Enter your DB User: " DB_USER
read -sp "Enter your DB Password: " DB_PASS
echo
read -p "Enter your DB Host: " DB_HOST
read -p "Enter your Redis Host: " REDIS_HOST
read -p "Enter your DB Name: " DB_NAME


read -p "Enter your REDIS_PASSWORD: " REDIS_PASSWORD
REDIS_PORT=6379

# Створюємо .env файл з чутливою інформацією


mkdir -p /var/www/$DOMAIN_NAME/public;
chown -R www-data:www-data /var/www/$DOMAIN_NAME/public;
chmod -R 755 /var/www;

cd /tmp
wget -c -q http://wordpress.org/latest.tar.gz
tar -xzf latest.tar.gz


cp -a /tmp/wordpress/. /var/www/$DOMAIN_NAME/public/
chown www-data:www-data -R /var/www/$DOMAIN_NAME/public/*
mkdir /var/www/$DOMAIN_NAME/public/wp-content/uploads
chmod 775 /var/www/$DOMAIN_NAME/public/wp-content/uploads



cp /var/www/$DOMAIN_NAME/public/wp-config-sample.php /var/www/$DOMAIN_NAME/public/wp-config.php

cat << EOF > /var/www/$DOMAIN_NAME/public/.env
DB_USER=$DB_USER
DB_PASS=$DB_PASS
DB_HOST=$DB_HOST
REDIS_HOST=$REDIS_HOST
REDIS_PORT=$REDIS_PORT
DB_NAME=$DB_NAME
REDIS_PASSWORD=$REDIS_PASSWORD
EOF

chown www-data:www-data /var/www/$DOMAIN_NAME/public/.env
chmod 640 /var/www/$DOMAIN_NAME/public/.env



# Install composer and phpdotenv
cd /var/www/$DOMAIN_NAME/public
apt install -y composer
composer require vlucas/phpdotenv


sed -i '1a\require_once __DIR__ . "/vendor/autoload.php";\n\n$dotenv = Dotenv\\Dotenv::createImmutable(__DIR__);\n$dotenv->load();' /var/www/$DOMAIN_NAME/public/wp-config.php

sed -i 's/\r$//' /var/www/$DOMAIN_NAME/public/wp-config.php


sed -i "s/'database_name_here'/\$_ENV['DB_NAME']/g" /var/www/$DOMAIN_NAME/public/wp-config.php
sed -i "s/'username_here'/\$_ENV['DB_USER']/g" /var/www/$DOMAIN_NAME/public/wp-config.php
sed -i "s/'password_here'/\$_ENV['DB_PASS']/g" /var/www/$DOMAIN_NAME/public/wp-config.php
sed -i "s/'localhost'/\$_ENV['DB_HOST']/g" /var/www/$DOMAIN_NAME/public/wp-config.php

sed -i "0,/^define/{//a\\
// Redis Configuration\n\
define('WP_CACHE', true);\n\
define('WP_REDIS_HOST', \$_ENV['REDIS_HOST']);\n\
define('WP_REDIS_PORT', \$_ENV['REDIS_PORT']);\n\
define('WP_REDIS_PASSWORD', \$_ENV['REDIS_PASSWORD']);\n\
define('WP_REDIS_SCHEME', 'tls');\n
}"  /var/www/$DOMAIN_NAME/public/wp-config.php



cat << EOF > /etc/nginx/conf.d/$DOMAIN_NAME.conf
server {
    listen 80;
    listen [::]:80;
    root /var/www/$DOMAIN_NAME/public;
    index  index.php index.html index.htm;
    server_name  $DOMAIN_NAME www.$DOMAIN_NAME;
    location / {
        try_files \$uri \$uri/ /index.php\$is_args;
    }
    location ~ \.php$ {
        fastcgi_split_path_info  ^(.+\.php)(/.+)$;
        fastcgi_index index.php;
        fastcgi_pass unix:/var/run/php/php8.3-fpm.sock;
        include fastcgi_params;
        fastcgi_param   PATH_INFO       \$fastcgi_path_info;
        fastcgi_param   SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }
}
EOF

sudo sed -i 's/^\s*#\s*server_names_hash_bucket_size\s*64;/server_names_hash_bucket_size 128;/' /etc/nginx/nginx.conf

nginx -t
echo "RESTART NGINX"
systemctl restart nginx