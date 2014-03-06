#!/bin/bash

#share-specific options
NFS_MOUNT='/mnt/share'
NFS_SHARE='192.168.0.1:/share'
NFS_OPTS='' #can be blank

#which path(s) to backup (space separated multiple paths possible)
SOURCE_PATH='/home/vagrant'
#directory to store the backup archives should start with $NFS_MOUNT/
TARGET_PATH="$NFS_MOUNT/zivi_backup_test"
#name of the archive: name_timestamp.tar.gz
BACKUP_NAME='testbackup'
#delete backups name_*.tar.gz older than
BACKUP_MAX_AGE='2 weeks ago' #1 month ago 

MOUNTBIN=`which mount`
TARBIN=`which tar`

function cleanup {
	touch -d "$BACKUP_MAX_AGE" $TARGET_PATH/date_marker
	TODEL=`find $TARGET_PATH \! -cnewer date_marker  -iname "${BACKUP_NAME}*.tar.gz"`
	for i in $TODEL;do
		rm $i
		echo "deleted $i"
	done
	rm $TARGET_PATH/date_marker

}

function archive {
	if [ ! -e $SOURCE_PATH ];then
		echo "$SOURCE_PATH does not exist. Nothing to do, exiting"
		exit 1
	fi
	
	if [ ! -d $TARGET_PATH ];then
		echo "$TARGET_PATH does not exist. creating…"
		mkdir -p $TARGET_PATH	
	fi

	TIMESTAMP=`date +%F_%H%M`
	TARGET_FILE="${TARGET_PATH}/${BACKUP_NAME}_$TIMESTAMP.tar.gz"
	TARCMD="$TARBIN -czvf $TARGET_FILE $SOURCE_PATH"
	eval $TARCMD
	if [ $? -eq 0 ];then
		echo "succesfully created $TARGET_FILE"
		ARCHIVE_RESULT='SUCCESS'
	else
		ARCHIVE_RESULT='FAIL'
		if [ -e $TARGET_FILE ];then 
			echo "removing failed backup: $TARGET_FILE"
			rm $TARGET_FILE
		fi
	fi
	
}

function check_share {
	CHECKCMD="/bin/grep -Fqe '$NFS_SHARE $NFS_MOUNT nfs rw' /etc/mtab"
	eval $CHECKCMD
	if [ $? -eq 0 ];then 
		CHECK_SHARE_RESULT='TRUE'
	else
		CHECK_SHARE_RESULT='FALSE'
	fi
}

function mount_share {
#mounting the nfs-share
	if [ ! -e /sbin/mount.nfs ];then
		echo -e "no helper program for mounting nfs share found!\n you have to install support for mounting nfs\n\ne.g in Debian do: sudo aptitude install nfs-client"
		exit 1
	fi

	if [ "$NFS_OPTSx" == "x"  ];then
		MOUNTCMD="$MOUNTBIN -t cifs $NFS_SHARE $NFS_MOUNT"
	else
		MOUNTCMD="$MOUNTBIN -t cifs $NFS_SHARE $NFS_MOUNT -o $NFS_OPTS"
	fi

	eval $MOUNTCMD

	if [ $? -ne 0 ];then
		MOUNT_SHARE_RESULT='FAIL'
	else
		MOUNT_SHARE_RESULT='SUCCESS'
	fi	
}

check_share
if [ $CHECK_SHARE_RESULT != 'TRUE' ];then	
	echo -e "share is not mounted!\ntrying to mount…"
	mount_share
	if [ $MOUNT_SHARE_RESULT == "SUCCESS" ];then
		echo -e "succesfully mounted share $NFS_SHARE on $NFS_MOUNT"
	fi
	if [ $MOUNT_SHARE_RESULT == "FAIL" ];then
		echo -e "not able to mount share!\n\"$MOUNTCMD\" failed\naborting"
		exit 1
	fi
fi
cleanup
archive
if [ $ARCHIVE_RESULT == 'FAIL' ];then
	echo -e "backup creation failed!\naborting"
	exit 1
fi

echo -e "finished backup, good bye\n"
exit 0
