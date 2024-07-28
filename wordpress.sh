#!/bin/bash 
clear
cat <<EOF
 ____________________________________________________________________
|                                                                    |
|   	===========================================                  |
|   	::..𝐓𝐡i𝐬 𝐬𝐞𝐫𝐯𝐞𝐫 𝐢𝐬 𝐬𝐞𝐭 𝐛𝐲 IntecHost.com...::     	     |
|   	===========================================                  |
|    	   ___________                                               |
|    	   < IntecHost >                                             |
|     	   -----------                                               |
|     	          \   ^__^                                           |
|     	           \  (oo)\_______                                   |
|     	              (__)\       )\/\                               |
|     	                  ||----w |                                  |
|     	                  ||     ||                                  |
|     	                                                             |
|   	===========================================                  |
|   	        www.IntecHost.com                                    |
|   	===========================================                  |       
|                                                                    |
|                                                                    |
|   Welcome to the Wordpress One-Click-App configuration.            |
|   			By IntecHost.com			     |
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
echo "============================================"
echo "          WordPress Install Script          "
echo "============================================"
echo

# Automatically generate database details and use the same password for the root user
dbhost="localhost"
dbname="wp_$(date +%s%N)"
dbuser="user_$(date +%s%N)"
dbpass=$(openssl rand -base64 12)
rootpass=$dbpass

#echo "Generated database details:"
#echo "Database Name: $dbname"
#echo "Database User: $dbuser"
#echo "Database Password: $dbpass"
#echo
#echo "MySQL Root Password: $rootpass"

echo
echo "=============Admin details=================="
echo -n "Site URL (e.g., example.com) : "
read siteurl
echo -n "Site Name (e.g., My Blog) : "
read sitename
echo -n "Admin Email Address : "
read wpemail
echo -n "Admin User Name : "
read wpuser
echo -n "Admin User Password : "
read -s wppass
echo
echo -n "Run install? (y/n) : "
read run

if [ "$run" == "n" ]; then
    exit
else
    echo
    echo "============================================"
    echo "A robot is now installing WordPress for you."
    echo "============================================"
    cd /var/www/html

    # Check if wp-cli is installed
    if ! command -v wp &> /dev/null; then
        echo "wp-cli not found, installing..."
        curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
        sudo mv wp-cli.phar /usr/local/bin/wp
        sudo chmod +x /usr/local/bin/wp
    fi

    # Create the database and user if they do not exist
    echo "Checking database..."
    mysql -u root -p"$rootpass" -e "CREATE DATABASE IF NOT EXISTS $dbname; CREATE USER IF NOT EXISTS '$dbuser'@'localhost' IDENTIFIED BY '$dbpass'; GRANT ALL PRIVILEGES ON $dbname.* TO '$dbuser'@'localhost'; FLUSH PRIVILEGES;"

    echo "Downloading the latest version of WordPress..."
    curl -O https://wordpress.org/latest.tar.gz
    echo "Extracting WordPress..."
    tar -zxvf latest.tar.gz
    cp -rf wordpress/* .
    rm -R wordpress
    rm latest.tar.gz

    echo
    echo "Creating wp-config.php..."
    cp wp-config-sample.php wp-config.php
    perl -pi -e "s/database_name_here/$dbname/g" wp-config.php
    perl -pi -e "s/username_here/$dbuser/g" wp-config.php
    perl -pi -e "s/password_here/$dbpass/g" wp-config.php
    perl -pi -e "s/localhost/$dbhost/g" wp-config.php

    mkdir -p wp-content/uploads
    chmod 777 wp-content/uploads

    echo
    echo "Installing WordPress..."
    wp core install --url="https://$siteurl/" --title="$sitename" --admin_user="$wpuser" --admin_password="$wppass" --admin_email="$wpemail" --allow-root

    # Install Let's Encrypt SSL certificate if requested
    echo
    read -p "Do you want to create a Let's Encrypt Certificate for Domain https://$siteurl/? (y/n): " ssl_confirm
    ssl_confirm=${ssl_confirm:-y}
    if [[ "$ssl_confirm" =~ ^[Yy]$ ]]; then
        echo "Installing Let's Encrypt SSL certificate..."
        certbot --apache -d $siteurl -m $wpemail --agree-tos --no-eff-email
    else
        echo "Skipping Let's Encrypt."
    fi

    echo "========================="
echo "Installation is complete."
echo
echo "Website URL: https://$siteurl/"
echo "Admin Access: https://$siteurl/wp-admin"
echo
echo "Username: $wpuser"
echo "Password: ******** (Your chosen password)"
echo "========================="
echo
echo "Thank you... IntecHost.com"

# Remove startup script from .bashrc
sed -i "/wordpress_setup/d" ~/.bashrc

# Prompt for server reboot
echo -en "\n\n"
while true
do
    read -p "Would you like to reboot the server now? [Y/n]: " reboot_confirm
    : ${reboot_confirm:="Y"}

    case $reboot_confirm in
        [yY][eE][sS]|[yY] ) echo "Rebooting the server..."; reboot; break;;
        [nN][oO]|[nN] ) echo "Reboot skipped."; break;;
        * ) echo "Please type y or n.";;
    esac
done

fi
