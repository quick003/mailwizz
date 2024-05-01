#!/bin/bash

echo "please create custom NS record 'ns1' value 'your_server_ip"
echo "please create custom NS record 'ns2' value 'your_server_ip"

echo "Do you want to continue running the script? (yes/no)"
read response

# Check the user's response
if [ "$response" = "yes" ]; then
    echo "Continuing the script..."
    # Add your script logic here
else
    echo "Exiting the script."
    exit 0
fi

yum update -y
yum install wget -y

read -p "Enter website domain: " domain
read -p "Enter website password: " password
db=$(echo "$domain" | cut -d '.' -f 1)
host="ns1"
read -p "Enter your ip: " serverip
read -p "Enter your username for PMTA: " pmtauser
read -sp "Enter your password for PMTA: " pmtapass

###set hostname
hostnamectl set-hostname $host.$domain

####installvirtualmin

wget http://software.virtualmin.com/gpl/scripts/install.sh
chmod a+x install.sh
sudo /bin/sh install.sh

###install otheeer version of php
. /etc/os-release && dnf -y install https://rpms.remirepo.net/enterprise/remi-release-$(rpm -E %$ID).rpm && dnf clean all

dnf install php81-php-{cli,fpm,pdo,gd,mbstring,mysqlnd,opcache,curl,xml,zip,imap,intl} -y


#### Create Weebsite
virtualmin create-domain --domain $domain --pass $password --unix --dir --webmin --web --dns --mail --mysql

###Create User
virtualmin create-user --domain $domain --user  support --pass $password --quota 1024 --real "Support"
virtualmin create-user --domain $domain --user  bounce --pass $password --quota 1024 --real "Bounce"
virtualmin create-user --domain $domain --user  feedback --pass $password --quota 1024 --real "FeedBack"


path="/home/$domain/public_html"
###Set PHP version
virtualmin set-php-directory --domain $domain --dir $path --version 8.1

###Database
virtualmin create-database --domain $domain --name $db --type mysql

virtualmin modify-dns --domain $domain --add-record "_dmarc txt v=DMARC1; p=none;"
virtualmin modify-dns --domain $domain --add-record "@ ns ns2.$domain"

#######
yum install opendkim-tools -y

# Define the domain for which you want to generate DKIM keys
DOMAIN="$domain"

# Define the directory where the DKIM keys will be stored
DKIM_DIR="/etc/opendkim/keys/${domain}"

# Create the directory if it doesn't exist
mkdir -p "$DKIM_DIR"

# Generate the DKIM keys using opendkim-genkey command
opendkim-genkey -b 2048 -d "$domain" -D "$DKIM_DIR" -s default

# Change ownership and permissions of the generated keys
chown opendkim:opendkim "${DKIM_DIR}/default.private"
chmod 400 "${DKIM_DIR}/default.private"
chmod 644 "${DKIM_DIR}/default.txt"

# Extract the DKIM TXT record value from the public key file
DKIM_TXT_RECORD="v=DKIM1;k=rsa;$(cat "$DKIM_DIR/default.txt" | awk 'NR == 2 || NR == 3 {print $1}')"

# Define the DNS zone file path
ZONE_FILE="/var/named/${domain}.zone"

# Define the name of the DKIM record (default._domainkey)
DKIM_RECORD_NAME="default._domainkey.${domain}."

virtualmin modify-dns --domain $domain --add-record "$DKIM_RECORD_NAME txt $DKIM_TXT_RECORD"

# Append the DKIM record to the DNS zone file
echo "$DKIM_RECORD_NAME IN TXT \"${DKIM_TXT_RECORD}\" >> $ZONE_FILE"

# Notify BIND to reload the zone (adjust the command based on your system)
sudo rndc reload


#################################################
##Mailwizz####

#file Download
wget -O mailwizz.zip https://www.dropbox.com/scl/fi/1i3bulddfnkdlk491rcf9/mailwizz.zip?rlkey=dqq1tuoash24p3s2k6m9x67ov

#moving file
source_path="/root/mailwizz.zip"
destination_path="/home/$db/public_html/"

# Check if the source file exists
if [ -f "$source_path" ]; then
    # Move the file to the destination
    mv "$source_path" "$destination_path"
    echo "File moved successfully!"
else
    echo "Source file does not exist."
fi

#unzip file
zip_file="/home/$db/public_html/mailwizz.zip"

# Destination directory for extracted files
destination="/home/$db/public_html/"

# Check if the ZIP file exists
if [ -f "$zip_file" ]; then
    # Unzip the file
    unzip "$zip_file" -d "$destination"
    echo "File successfully unzipped!"
else
    echo "ZIP file does not exist."
fi

chown $db:$db -R /home/$db/public_html/*

####################

#### Database

MYSQL_USER="root"
DATABASE_NAME="$db"
DATABASE_USER="mail_db"
file="/home/$db/public_html/apps/common/config/main-custom.php"

sed -i "s/dbname=swgsv_com/dbname=$db/" "$file"
sed -i "s/swgsv_com/$DATABASE_USER/" "$file"

git clone https://github.com/quick003/ritik.git

 #Create the user
mysql -u $MYSQL_USER -e "CREATE USER '$DATABASE_USER'@'localhost' IDENTIFIED BY 'pradeep';"

# Grant privileges 	to the user on the database
mysql -u $MYSQL_USER -e "GRANT ALL PRIVILEGES ON $DATABASE_NAME.* TO '$DATABASE_USER'@'localhost';"

# Flush privileges
mysql -u $MYSQL_USER -e "FLUSH PRIVILEGES;"

mysql -D $db < /root/ritik/swdlv.sql

# to insert delivery,feedback, bounce server
SQL_STATEMENT_1="UPDATE mw_delivery_server SET hostname='$host.$domain',username='$pmtauser',password='$pmtapass',from_email='support@$domain' WHERE 1;"
SQL_STATEMENT_2="UPDATE mw_bounce_server SET hostname='$host.$domain',username='bounce@$domain',password='$password',email='bounce@$domain' WHERE 1;"
SQL_STATEMENT_3="UPDATE mw_feedback_loop_server SET hostname='$host.$domain',username='feedback@$domain',password='$password',email='feedback@$domain' WHERE 1;"

mysql -u $MYSQL_USER $DATABASE_NAME -e "$SQL_STATEMENT_1"
mysql -u $MYSQL_USER $DATABASE_NAME -e "$SQL_STATEMENT_2"
mysql -u $MYSQL_USER $DATABASE_NAME -e "$SQL_STATEMENT_3"

### cron jobs

echo "$(crontab -l)"$'\n'"* * * * * /opt/remi/php81/root/usr/bin/php -q /home/$db/public_html/apps/console/console.php send-campaigns >/dev/null 2>&1" | crontab -
echo "$(crontab -l)"$'\n'"* * * * * /opt/remi/php81/root/usr/bin/php -q /home/$db/public_html/apps/console/console.php queue >/dev/null 2>&1" | crontab -
echo "$(crontab -l)"$'\n'"*/2 * * * * /opt/remi/php81/root/usr/bin/php -q /home/$db/public_html/apps/console/console.php send-transactional-emails >/dev/null 2>&1" | crontab -
echo "$(crontab -l)"$'\n'"*/10 * * * * /opt/remi/php81/root/usr/bin/php -q /home/$db/public_html/apps/console/console.php bounce-handler >/dev/null 2>&1" | crontab -
echo "$(crontab -l)"$'\n'"*/20 * * * * /opt/remi/php81/root/usr/bin/php -q /home/$db/public_html/apps/console/console.php feedback-loop-handler >/dev/null 2>&1" | crontab -
echo "$(crontab -l)"$'\n'"*/3 * * * * /opt/remi/php81/root/usr/bin/php -q /home/$db/public_html/apps/console/console.php process-delivery-and-bounce-log >/dev/null 2>&1" | crontab -
echo "$(crontab -l)"$'\n'"0 * * * * /opt/remi/php81/root/usr/bin/php -q /home/$db/public_html/apps/console/console.php hourly >/dev/null 2>&1" | crontab -
echo "$(crontab -l)"$'\n'"0 0 * * * /opt/remi/php81/root/usr/bin/php -q /home/$db/public_html/apps/console/console.php daily >/dev/null 2>&1" | crontab -
echo "Cron job added successfully."
sleep 2s

#####################
#installing pmta

#update firewall
firewall-cmd --permanent --add-port=10719/tcp
firewall-cmd --permanent --add-port=2525/tcp
firewall-cmd --reload

#install pmta
yum install wget perl vim -y
wget -O install.sh https://www.dropbox.com/s/d7kfwr2zzakrs47/installpmta5r7.sh
chmod +x install.sh
./install.sh

#delete old config and download new config
rm -rf /etc/pmta/config

wget https://www.dropbox.com/s/f46jmke71r6jziu/config
source_path="/root/config"
destination_path="/etc/pmta/config"

# Check if the source file exists
if [ -f "$source_path" ]; then
    # Move the file to the destination
    mv "$source_path" "$destination_path"
    echo "File moved successfully!"
else
    echo "Source file does not exist."
fi

config_file="/etc/pmta/config"

sed -i "s/postmaster admin@domain.com/postmaster admin@$domain/" "$config_file"
sed -i "s/smtp-listener server_ip:2525/smtp-listener $serverip:2525/" "$config_file"
sed -i "s/<smtp-user pmtauser>/<smtp-user $pmtauser>/" "$config_file"
sed -i "s/password pmtapass/password $pmtapass/" "$config_file"
sed -i "s/smtp-source-host server_ip hostname/smtp-source-host $serverip $host.$domain/" "$config_file"
sed -i "s/domain12/$domain/" "$config_file"
sed -i "s/<domain domain.com>/<domain $domain>/" "$config_file"

service pmta start
service pmtahttp restart

echo "your mailwizz link is https://$domain/backend/index.php/guest/index"
echo "your mailwizz login id is admin@domain.com"
echo "your mailwizz login password is 12345678 pls change it as soon as possible"
echo ""
echo ""
echo "Virtualmin Access"
echo "https://$domain:10000"
echo "user-root pass-your_server_password"
echo ""
echo ""
echo "Your Email Access https://$domain:20000"
echo "email-bounce@$domain pass-$password"
echo "email-feedback@$domain pass-$password"
echo "email-support@$domain pass-$password"
echo ""
echo ""
echo "PMTA Acess"
echo "host-$host.$domain port-2525"
echo "user-$pmtauser pass-$pmtapass"

