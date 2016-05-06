#!/bin/bash
#title           : backup.sh
#description     : This script make a backup from a dir and a mysql docker container
#author		       : William Bartolini <contact@williambartolini.fr>
#date            : 20160506
#version         : 1
#notes           : The mysql container must use the official image and mount the dest
#                  dir of the sql dump into /var/mysqldump
#usage		       : bash backup.sh
#==============================================================================

# Dir of files to dump
PUBLIC_HTML="/var/public_html"
# Dir that where the sql dump will go
MYSQL_DUMP="/var/mysqldump"

# Servername to write in emails
SERVERNAME="Serveur de test"
# sysadmin name for emails
SYSADMINNAME="William Bartolini"
# Prefix name for the backup file
FILENAME="SERVERTEST"
# Email that will get email
REPORT_EMAIL="report@williambartolini.fr"

# SQL Credentials
MYSQL_CONTAINER="mysqlcontainer" # Name of the container running the official mysql image
MYSQL_DB=""
MYSQL_USER=""
MYSQL_PASSWD=""

# FTP credentials
FTP_HOST="localhost"
FTP_PORT="21"
FTP_USER=""
FTP_PASSWD=""

TMP_DIR=""

function clearTmp {
  if [ ! -z "$TMP_DIR" ]; then
    echo "Removing tmp dir ${TMP_DIR}"
    rm -R $TMP_DIR
  else
    echo "Empty var TMP_DIR, abort..."
    exit 1
  fi
}
function quit {
   if [ $1 == "stopped_container" ]; then
    clearTmp
    echo "Script stopped because the mysql container is not running."
    mail -s "Failed backup(stopped_container) of $SERVERNAME" "$REPORT_EMAIL" <<EOF
Dear ${SYSADMINNAME},

The backup of ${SERVERNAME} has failed because the mysql container wasn't running.
Please check if the server is up.

Thanks for using our product,
The best developper in the world.
EOF
   elif [ $1 == "missing_container" ]; then
    clearTmp
    echo "Script stopped because the mysql container is missing."
    mail -s "Failed backup(missing_container) of $SERVERNAME" "$REPORT_EMAIL" <<EOF
Dear ${SYSADMINNAME},

The backup of ${SERVERNAME} has failed because the mysql container is missing.
Please check if the server is up.

Thanks for using our product,
The best developper in the world.
EOF
   elif [ $1 == "unreachable_ftp" ]; then
     clearTmp
     echo "Script stopped because the ftp server is unreachable."
     mail -s "Failed backup(unreachable_ftp) of $SERVERNAME" "$REPORT_EMAIL" <<EOF
Dear ${SYSADMINNAME},

The backup of ${SERVERNAME} has failed because the FTP server was unreachable at the time of the backup.
Please check if the server is up and eventually trigger manually another backup.

Thanks for using our product,
The best developper in the world.
EOF
   elif [ $1 == "superuser" ]; then
     echo "You must run this script without superpower"
     mail -s "Failed backup(superuser) of $SERVERNAME" "$REPORT_EMAIL" <<EOF
Dear ${SYSADMINNAME},

The backup of ${SERVERNAME} has failed because user root attempted to run the script.
The server security might be threatened, please check logs right now.

Thanks for using our product,
The best developper in the world.
EOF
   elif [ $1 == "success" ]; then
     echo "Send email report to sysadmin"
     mail -s "Success backup of $SERVERNAME" "$REPORT_EMAIL" <<EOF
    Dear ${SYSADMINNAME},

    The backup of ${SERVERNAME} has ended successfully.

    The final backup is ${BACKUP_FILENAME} with a size of ${BACKUP_FILESIZE}.
    The database size was ${SQL_FILESIZE}.

    Thanks for using our product,
    The best developper in the world.
EOF
     clearTmp
     exit 0
   fi

   exit 1
}

echo "Backup script started"

if [ $(id -u) = "0" ]; then
    quit "superuser"
fi

echo "Creating tmp dir"

if [ ! -d "/tmp/server_backup" ]; then
  mkdir /tmp/server_backup
  TMP_DIR="/tmp/server_backup"
else
  i=0
  while [ -d "/tmp/server_backup_$i" ]; do
    i=$((i+1))
  done
  mkdir /tmp/server_backup_$i
  TMP_DIR="/tmp/server_backup_$i"
fi

echo "Tmp dir created at ${TMP_DIR}"
echo "Copy files from ${PUBLIC_HTML}/ to ${TMP_DIR}/public_html/"

cp -R "$PUBLIC_HTML" "$TMP_DIR/public_html/"

echo "Getting mysql container id"

CONTAINER_ID=$(docker ps -aqf name=$MYSQL_CONTAINER)
if [ -z $CONTAINER_ID ]; then
  quit "missing_container"
fi
echo "Found id $CONTAINER_ID for container $MYSQL_CONTAINER"

echo "Dumping the database"
if ! docker exec "$CONTAINER_ID" touch "/var/mysqldump/$MYSQL_DB.sql"; then
  quit "stopped_container"
fi
docker exec "$CONTAINER_ID" mysqldump --user="$MYSQL_USER" --password="$MYSQL_PASSWD" --result-file="/var/mysqldump/$MYSQL_DB.sql" "$MYSQL_DB"
docker exec "$CONTAINER_ID" chmod 777 "/var/mysqldump/$MYSQL_DB.sql"

echo "Move sql dump to $TMP_DIR/sql/"
mkdir "$TMP_DIR/sql/"
mv "$MYSQL_DUMP/$MYSQL_DB.sql" "$TMP_DIR/sql/$MYSQL_DB.sql"

SQL_FILESIZE=$(ls -lh ${TMP_DIR}/sql/${MYSQL_DB}.sql | cut --delimiter=" " -f5)

echo "Compressing sql dump and public_html"
mkdir "$TMP_DIR/archive/"
mv "$TMP_DIR/sql/" "$TMP_DIR/archive/"
mv "$TMP_DIR/public_html/" "$TMP_DIR/archive/"

BACKUP_FILENAME="$FILENAME_$(date +%Y_%m_%d_%H_%M_%S).tar.gz"
tar -zcf $TMP_DIR/$BACKUP_FILENAME "$TMP_DIR/archive/"

BACKUP_FILESIZE=$(ls -lh ${TMP_DIR}/${BACKUP_FILENAME} | cut --delimiter=" " -f5)
rm -R "$TMP_DIR/archive/"

echo "Send backup to ftp server"

  ftpexit=$(ftp -in <<EOF
open ${FTP_HOST} ${FTP_PORT}
user ${FTP_USER} ${FTP_PASSWD}
cd ~/backup/
lcd ${TMP_DIR}
put ${BACKUP_FILENAME}
close
bye
EOF
)
ftpexit=$(echo $ftpexit | cut --delimiter="." -f1)

if [ "$ftpexit" == "Not connected" ]; then
  quit "unreachable_ftp"
fi

quit "success"

