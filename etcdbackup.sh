#!/bin/bash
# refer https://github.com/etcd-io/etcd/blob/master/Documentation/op-guide/recovery.md
# TODO: restore from backup
# ETCDCTL_API=3 etcdctl --endpoints $ENDPOINT snapshot save snapshot.db

## Positional Parameters

ARGS=`getopt -o h --long help,apiversion:,plan:,remote: -- "$@"`
if [ $? != 0 ] ; then echo "Terminating..." >&2 ; exit 1 ; fi
eval set -- "$ARGS"
while true; do
    case $1 in
        --apiversion)
            ETCD_VERSION=$2
            echo "etcd API version: ${ETCD_VERSION}"
            shift 2
            ;;
        --plan)
            ETCD_BACKUP_INTERVAL=$2
            echo "backup plan: ${ETCD_BACKUP_INTERVAL}"
            shift 2
            ;;
        --remote)
            REMOTE_ADDRESS=$2
            echo "upload file to: ${REMOTE_ADDRESS}"
            shift 2
            ;;
        -h | --help)
            echo "Available options for etcd_backup script:"
            echo -e "\n --apiversion string(current only support 3)         Sets etcd backup version to etcdv3 API. This will not include v2 data."
            echo -e "\n --plan daily || hourly         Sets the backup location to the daily or hourly directory."
            echo -e "\n --remote string         Sets the backup location to the daily or hourly directory."
            echo -e "\n -h | --help      Shows this help output."
            shift
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "invalid option specified"
            exit 1
            ;;
    esac
done

## Variables
# TLS settings
source /etc/etcd.env

ETCD_DATA_DIR=/var/lib/etcd
ETCD_BACKUP_PREFIX=/var/lib/etcd/backups/$ETCD_BACKUP_INTERVAL 
ETCD_BACKUP_DIRECTORY=$ETCD_BACKUP_PREFIX/etcd-$(date +"%F")_$(date +"%T")
ETCD_ENDPOINTS=https://192.168.99.31:2379,https://192.168.99.32:2379,https://192.168.99.33:2379

REMOTE_USER=root
REMOTE_DIRECTORY="/test"

## Functions
upload_file(){
  # ensure the network connection
  # ssh without password or change there with password.
  ssh ${REMOTE_USER}@${REMOTE_ADDRESS} "[[ -d ${REMOTE_DIRECTORY} ]] && echo ok || mkdir -p ${REMOTE_DIRECTORY}" 
  scp -rp ${ETCD_BACKUP_DIRECTORY} root@${REMOTE_ADDRESS}:${REMOTE_DIRECTORY}
  if [[ $? -ne 0 ]]; then
      echo -e "\033[31mscp backup file to ${REMOTE_ADDRESS}/${REMOTE_DIRECTORY} failed.\033[0m"
      echo "scp backup file to ${REMOTE_ADDRESS}/${REMOTE_DIRECTORY} failed." | systemd-cat -t upload_file -p err
  else
      echo -e "\033[32mscp backup file to ${REMOTE_ADDRESS}/${REMOTE_DIRECTORY} completed successfully.\033[0m"
      echo "scp backup file to ${REMOTE_ADDRESS}/${REMOTE_DIRECTORY} completed successfully." | systemd-cat -t upload_file -p info
  fi
}

backup_etcdv3(){
  # create the backup directory if it doesn't exist
  [[ -d $ETCD_BACKUP_DIRECTORY ]] || mkdir -p $ETCD_BACKUP_DIRECTORY
  ETCDCTL_API=3 /usr/local/bin/etcdctl --endpoints $ETCD_ENDPOINTS --cert=$ETCD_CERT_FILE --cacert=$ETCD_TRUSTED_CA_FILE --key=$ETCD_KEY_FILE snapshot save $ETCD_BACKUP_DIRECTORY/snapshot.db
  if [[ $? -ne 0 ]]; then
      echo -e "\033[31metcdv$ETCD_VERSION $ETCD_BACKUP_INTERVAL backup failed on ${HOSTNAME}.\033[0m"
      echo "etcdv$ETCD_VERSION $ETCD_BACKUP_INTERVAL backup failed on ${HOSTNAME}." | systemd-cat -t upload_file -p err
  else
      echo -e "\033[32metcdv$ETCD_VERSION $ETCD_BACKUP_INTERVAL backup completed successfully.\033[0m"
      echo "etcdv$ETCD_VERSION $ETCD_BACKUP_INTERVAL backup completed successfully." | systemd-cat -t upload_file -p info
  fi
}

# check if backup interval is set
if [[ -z "$ETCD_BACKUP_INTERVAL" ]]; then
    echo "You must set a backup interval. Use either the --hourly or --daily option."
    echo "See -h | --help for more information."
    exit 1
fi

# run backups and log results
if [[ "$ETCD_VERSION" = "3" ]]; then
    backup_etcdv3
    upload_file
else
    echo "You must set an etcd version. Use either the --etcdv2 or --etcdv3 option."
    echo "See -h | --help for more information."
    exit 1
fi
