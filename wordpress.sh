#!/bin/bash

sudo apt update -y
sudo apt install apache2 -y
sudo systemctl enable apache2
sudo systemctl start apache2
sudo apt install certbot python3-certbot-apache -y
sudo apt install php -y
sudo apt install php-curl php-json php-mbstring -y
sudo apt install php-mysqli -y
sudo apt install mysql-client -y
sudo apt install mariadb-client -y
sudo apt-get install mysql-server -y
clear

set -e

cat <<EOF
 ____________________________________________________________________
|                                                                    |
|    ===========================================                     |
|    ::..𝐓𝐡i𝐬 𝐬𝐞𝐫𝐯𝐞𝐫 𝐢𝐬 𝐬𝐞𝐭 𝐛𝐲 IntecHost.com...::              |
|    ===========================================                     |
|       ___________                                                  |
|       < IntecHost >                                                |
|       -----------                                                  |
|              \   ^__^                                              |
|               \  (oo)\_______                                      |
|                  (__)\       )\/\                                  |
|                      ||----w |                                     |
|                      ||     ||                                     |
|                                                                    |
|    ===========================================                     |
|            www.IntecHost.com                                       |
|    ===========================================                     |
|                                                                    |
|   Welcome to the Wordpress One-Click-App configuration.            |
|           By IntecHost.com                                         |
|                                                                    |
|   In this process Wordpress will be set up accordingly.            |
|   You only need to set your desired Domain and a few Wordpress     |
|   details. You can also decide if Let's Encrypt should obtain      |
|   a valid SSL Certificate.                                         |
|   Please make sure your Domain exists first.                       |
|                                                                    |
|   Please enter the Domain in following pattern: your.example.com   |
|____________________________________________________________________|
EOF

user_input(){
  while [ -z "$domain" ]
  do
    read -p "Your Domain: " domain
  done

  while true
  do
    read -p "Your Email Address (for Wordpress Account): " email
    if grep -oP '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}$' <<<"$email" >/dev/null 2>&1; then
      break
    else
      echo "Please enter a valid E-Mail."
    fi
  done

  while [ -z "$username" ]
  do
    read -p "Your Username [Default=admin]: " username
    username=${username:-admin}
  done

  while true
  do
    read -s -p "Password: " password
    echo
    read -s -p "Password (again): " password2
    echo
    [ "$password" = "$password2" ] && break || echo "Please try again"
  done

  read -p "Wordpress Title: " title

  db_name="wp_$(date +%s%N)"

  db_user="user_$(date +%s%N)"

  db_password=$(openssl rand -base64 12)

  db_host="localhost"
  
  rootpass=$db_password

  read -p "Table Prefix [Default=wp_]: " table_prefix
  table_prefix=${table_prefix:-wp_}
}

certbot_crontab() {
  echo -en "\n"
  echo "Setting up Crontab for Let's Encrypt."
  crontab -l > certbot || true
  echo "30 2 * * 1 /usr/bin/certbot renew >> /var/log/le-renew.log" >> certbot
  echo "35 2 * * 1 systemctl reload apache2" >> certbot
  crontab certbot
  rm certbot
}

echo -en "\n"
echo "Please enter your details to set up your new Wordpress Instance."

user_input

while true
do
    echo -en "\n"
    read -p "Is everything correct? [Y/n] " confirm
    confirm=${confirm:-Y}

    case $confirm in
      [yY][eE][sS]|[yY] ) break;;
      [nN][oO]|[nN] ) unset domain email username password title db_name db_user db_password db_host table_prefix; user_input;;
      * ) echo "Please type y or n.";;
    esac
done

# set domain_is_www variable
if [[ $domain == "www."* ]]; then domain_is_www=true; else domain_is_www=false; fi

sed -i "s/\$domain/$domain/g" /etc/apache2/sites-enabled/000-default.conf

# create webserver folder and remove static page
if [[ -d /var/www/wordpress ]]
then
  rm -rf /var/www/html
  mv /var/www/wordpress /var/www/html
  chown -Rf www-data:www-data /var/www/html
  systemctl restart apache2
fi

# Enable necessary Modules
a2enmod dir
a2enmod rewrite
a2enmod socache_shmcb
a2enmod ssl

echo -en "\n\n"
echo -en "Do you want to create a Let's Encrypt Certificate for Domain $domain? \n"
read -p "Note that the Domain needs to exist. [Y/n]: " le
le=${le:-Y}
case $le in
    [Yy][eE][sS]|[yY] )
      while true
      do
        read -p "Your Email Address (for Let's Encrypt Notifications): " le_email
        if grep -oP '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,24}$' <<<"$le_email" >/dev/null 2>&1; then
          break
        else
          echo "Please enter a valid E-Mail."
        fi
      done
      if [[ $domain_is_www = true ]]; then
        certbot --noninteractive --apache -d $domain --agree-tos --email $le_email --no-redirect
      elif [[ $domain_is_www = false ]]; then
        certbot --noninteractive --apache -d $domain --agree-tos --email $le_email --redirect
      fi
      domain_use_https=true
      certbot_crontab;;
    [nN][oO]|[nN] ) echo -en "\nSkipping Let's Encrypt.\n"; domain_use_https=false;;
    * ) echo "Please type y or n.";;
esac

# set redirects for www domain
if [[ $domain_is_www = true ]] && [[ $domain_use_https = true ]]; then
    cat << EOF >> /var/www/html/.htaccess
  RewriteEngine on
  RewriteCond %{HTTPS} off [OR]
  RewriteCond %{HTTP_HOST} !^www\. [NC]
  RewriteRule (.*) https://$domain%{REQUEST_URI} [R=301,L]
EOF
elif [[ $domain_is_www = true ]] && [[ $domain_use_https = false ]]; then
    cat << EOF >> /var/www/html/.htaccess
  RewriteEngine on
  RewriteCond %{HTTP_HOST} !^www\. [NC]
  RewriteRule (.*) http://$domain%{REQUEST_URI} [R=301,L]
EOF
fi
systemctl restart apache2

# install wp cli and configure WP
wget https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar -O /usr/bin/wp
chmod +x /usr/bin/wp

# Download WordPress core files
wp core download --allow-root --path="/var/www/html"

# Create the database and user if they do not exist
    echo "Checking database..."
    mysql -u root -p"$rootpass" -e "CREATE DATABASE IF NOT EXISTS $db_name; CREATE USER IF NOT EXISTS '$db_user'@'localhost' IDENTIFIED BY '$db_password'; GRANT ALL PRIVILEGES ON $db_name.* TO '$db_user'@'localhost'; FLUSH PRIVILEGES;"
    
echo "Creating wp-config.php..."
    cd /var/www/html
    cp wp-config-sample.php wp-config.php
    perl -pi -e "s/database_name_here/$db_name/g" wp-config.php
    perl -pi -e "s/username_here/$db_user/g" wp-config.php
    perl -pi -e "s/password_here/$db_password/g" wp-config.php
    perl -pi -e "s/localhost/$db_host/g" wp-config.php

# Install WordPress
wp core install --allow-root --path="/var/www/html" --title="$title" --url="$domain" --admin_email="$email" --admin_password="$password" --admin_user="$username"

chown -Rf www-data:www-data /var/www/
cp /etc/skel/.bashrc /root

echo -en "\n\n"
echo "The installation is complete and Wordpress should be running at your Domain."
echo "--- $domain ---"
echo -en "\n"
echo "The Admin Panel can be accessed via"
echo "--- $domain/wp-admin ---"
echo -en "\n"

# Remove startup script from .bashrc
sed -i "/wordpress_setup/d" ~/.bashrc

# Prompt for server reboot
echo -en "\n\n"
while true
do
    read -p "Would you like to reboot the server now? [Y/n]: " reboot_confirm
    reboot_confirm=${reboot_confirm:-Y}

    case $reboot_confirm in
        [yY][eE][sS]|[yY] ) echo "Rebooting the server..."; reboot; break;;
        [nN][oO]|[nN] ) echo "Reboot skipped."; break;;
        * ) echo "Please type y or n.";;
    esac
done
