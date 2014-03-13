#!/bin/bash

LVM_VG="zivi"
LVM_LV="root"
LVM_LV_SNAPSHOT_NAME="${LVM_LV}-backup"
LVM_LV_SNAPSHOT_SIZE="5" # IN GB
LVM_LV_SNAPSHOT_MOUNT="/mnt/lvmsnapshots/${LVM_LV_SNAPSHOT_NAME}"

USE_NFS_TARGET=1 #0 use NFS-target, 1 dont use NFS-target
#share-specific options
NFS_MOUNT='/mnt/share'
NFS_SHARE='192.168.0.1:/share'
NFS_OPTS='' #can be blank
#directory to store the backup archives should start with $NFS_MOUNT/ if USE_NFS_TARGET is set to 0

#TARGET_PATH="$NFS_MOUNT/zivi_backup_test"
BACKUP_TARGET_PATH="/mnt/backuptest"
#name of the archive: name_timestamp.tar.gz
BACKUP_NAME='testbackup'
#delete backups name_*.tar.gz older than
BACKUP_MAX_AGE='2 weeks ago' #1 month ago 

MOUNTBIN=`which mount`
UMOUNTBIN=`which umount`
TARBIN=`which tar`

VG_CHECK=1
LV_CHECK=1
SNAPSHOT_CHECK=1
MOUNT_CHECK=1

function check_vg {
	/sbin/vgdisplay $LVM_VG > /dev/null
	if [ $? != 0 ];then 
		echo -e "Logical Volume Group: $LVM_VG probably does not exist\naborting…"
		exit 1
	fi
	#check Free space on VG 
	VG_FREE_SPACE=`/sbin/vgdisplay $LVM_VG -C -o vg_free --units g --noheadings --nosuffix | sed 's/\([[:digit:]]\)\,\([[:digit:]]\)/\1.\2/g'`
	if (( ! $(echo "${VG_FREE_SPACE} >= ${LVM_LV_SNAPSHOT_SIZE}" |bc -l ) ));then
		echo -e "not enough free space on Logical Volume Group: $LVM_VG for snapshotting\naborting…"
		exit 1
	fi
	VG_CHECK=0
}

function check_lv {
	/sbin/lvdisplay /dev/${LVM_VG}/${LVM_LV}	> /dev/null
  if [ $? != 0 ];then
    echo -e "Logical Volume: $LVM_LV probably does not exist or is not located in volume group: $LVM_VG\n"
    exit 1
  fi
	LV_CHECK=0
}

function check_for_snapshot {
	/sbin/lvdisplay /dev/${LVM_VG}/${LVM_LV_SNAPSHOT_NAME} > /dev/null 2>&1
  if [ $? -eq  0 ];then
    echo -e "Logical Volume: with name ${LVM_LV_SNAPSHOT_NAME} already exists in Volume Group: ${LVM_VG}\naborting…"
    exit 1
  fi
  SNAPSHOT_CHECK=0
}

function create_snapshot {
	/sbin/lvcreate -L${LVM_LV_SNAPSHOT_SIZE}G -s -n ${LVM_LV_SNAPSHOT_NAME} /dev/${LVM_VG}/${LVM_LV} 
	if [ $? -ne 0 ];then 
		echo -e "cant create LVM-snapshot\naborting…"
		exit 1
	fi
}

function remove_snapshot {
	/sbin/lvremove -f /dev/${LVM_VG}/${LVM_LV_SNAPSHOT_NAME} 
	if [ $? -ne 0 ];then 
		echo -e "cant remove LVM-snapshot\naborting…"
		exit 1
	fi
}

function check_mount {
	MOUNT_CHECK=1
	if [ ! -e $1 ];then 
		echo -e "mountpoint $1 does not exist.\ntrying to create it for you"
		mkdir -p $1
		if [ $? != 0 ];then 
			echo -e "cant create mountpoint $1\naborting…"
			exit 1
		fi
	elif [ ! -d $1 ];then 
		echo "given mountpoint $1 already exists but is no usable directory\naborting…"
		exit 1
	fi

	MOUNT_CHECK=0
}

function mount_snapshot {
	#check that nothing else is mounted there
	$MOUNTBIN -f /dev/${LVM_VG}/${LVM_LV_SNAPSHOT_NAME} ${LVM_LV_SNAPSHOT_MOUNT} 
	if [ $? != 0 ];then 
		echo "could not fake mount /dev/${LVM_VG}/${LVM_LV_SNAPSHOT_NAME} on ${LVM_LV_SNAPSHOT_MOUNT}\naborting…"
		exit 1
	fi
	
	$MOUNTBIN /dev/${LVM_VG}/${LVM_LV_SNAPSHOT_NAME} ${LVM_LV_SNAPSHOT_MOUNT}
	if [ $? != 0 ];then 
		echo -e "could not mount /dev/${LVM_VG}/${LVM_LV_SNAPSHOT_NAME} on ${LVM_LV_SNAPSHOT_MOUNT}\naborting…"
		exit 1
	fi
}

function umount_snapshot {
	$UMOUNTBIN /dev/${LVM_VG}/${LVM_LV_SNAPSHOT_NAME}
	if [ $? != 0 ];then 
		echo -e "could not umount /dev/${LVM_VG}/${LVM_LV_SNAPSHOT_NAME}\naborting…"
		exit 1
	fi
}

function mount_nfs_share {
#mounting the nfs-share
  if [ ! -e /sbin/mount.nfs ];then
    echo -e "no helper program for mounting nfs share found!\n you have to install support for mounting nfs\n\ne.g in Debian do: sudo aptitude install nfs-client"
    exit 1
  fi

  if [ ! -d $NFS_MOUNT ];then
     echo -e "given nfs-mountpoint does not exist\ncreating $NFS_MOUNT"
     mkdir -p $NFS_MOUNT
     if [ $? != 0 ];then
       echo -e "cant create mountpoint $NFS_MOUNT\naborting"
       exit 1
     fi
  fi

  if [ "$NFS_OPTSx" == "x"  ];then
    MOUNTCMD="$MOUNTBIN -t nfs $NFS_SHARE $NFS_MOUNT"
  else
    MOUNTCMD="$MOUNTBIN -t nfs $NFS_SHARE $NFS_MOUNT -o $NFS_OPTS"
  fi

  eval $MOUNTCMD

  if [ $? -ne 0 ];then
    MOUNT_SHARE_RESULT='FAIL'
  else
    MOUNT_SHARE_RESULT='SUCCESS'
  fi
}

function archive {
  TIMESTAMP=`date +%F_%H%M`
  TARGET_FILE="${BACKUP_TARGET_PATH}/${BACKUP_NAME}_$TIMESTAMP.tar.gz"
  TARCMD="$TARBIN -czvf $TARGET_FILE -C ${LVM_LV_SNAPSHOT_MOUNT} ."
  eval $TARCMD > /dev/null
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

function cleanup {
  touch -d "$BACKUP_MAX_AGE" $BACKUP_TARGET_PATH/date_marker
  TODEL=`find $BACKUP_TARGET_PATH \! -cnewer $BACKUP_TARGET_PATH/date_marker  -iname "${BACKUP_NAME}*.tar.gz"`
  for i in $TODEL;do
    rm $i
    echo "deleted $i"
  done
  rm $BACKUP_TARGET_PATH/date_marker
}

check_vg
check_lv
check_for_snapshot
check_mount ${LVM_LV_SNAPSHOT_MOUNT}

#if [ $MOUNT_CHECK -eq 0 ]
if [ ${USE_NFS_TARGET} -eq 0 ];then 
	check_mount ${NFS_MOUNT}
  CHECKCMD="/bin/grep -Fqe '$NFS_SHARE $NFS_MOUNT nfs rw' /etc/mtab"
  eval $CHECKCMD
  if [ $? -eq 0 ];then
    CHECK_SHARE_RESULT='TRUE'
  else
    CHECK_SHARE_RESULT='FALSE'
		mount_nfs_share
		if [ $MOUNT_SHARE_RESULT != "SUCCESS" ];then
			echo -e "could not mount nfs-share $NFS_SHARE on $NFS_MOUNT\naborting…"
			exit 1
		else
			echo -e "succesfully mounted share $NFS_SHARE on $NFS_MOUNT\n"
			CHECK_SHARE_RESULT='TRUE'
		fi
 	fi
fi

if [ ! -d $BACKUP_TARGET_PATH ];then
  echo "$BACKUP_TARGET_PATH does not exist. creating…"
  mkdir -p $BACKUP_TARGET_PATH
fi

create_snapshot
mount_snapshot
archive
#echo -e "VG_CHECK: ${VG_CHECK}\nLV_CHECK: ${LV_CHECK}\nSNAPSHOT_CHECK: ${SNAPSHOT_CHECK}\nMOUNT_CHECK: ${MOUNT_CHECK}"
if [ $ARCHIVE_RESULT == 'FAIL' ];then
  echo -e "backup creation failed!\ncleaning up"
  umount_snapshot
	remove_snapshot
	exit 1
fi

cleanup
umount_snapshot
remove_snapshot
echo -e "finished backup, good bye\n"
exit 0
