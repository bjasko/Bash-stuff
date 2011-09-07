#!/bin/bash

# Shell : Bash
# Description : Small nova-volumes backup script
# Author : razique.mahroua@gmail.com
# Actual version : Version 00

# 		Revision note    
# V00 : Initial version
# V01 : The "create_tar" function has been modified, is uses now the second parameter in order to get the volume name
  
#  		Notes    	
# This script is meant to be launched from you cloud-manager server. It connects to all running instances, 
# runs a mysqldump (Debian flavor), mounts the snapshoted LVM volumes and create a TAR on a destination directory. You can disable the mysqldumps if you don't use mysql/ or debian's instances.
# The script can be croned everyday, a rotation makes sure that only a backup per day, for a week exists, while older ones are deleted. When the backup is over, an email is sent to you, with some details.

# A test mode "lvm_limit_one" is available, it allows you to run the whole script for only one LVM volume.
	
# 		Usage
# chmod +x SCR_5005_$version_NUAC-EBS-volumes-backup.sh
# ./SCR_5005_$version_NUAC-EBS-volumes-backup.sh           

# Binaries
	MOUNT=/bin/mount
	UMOUNT=/bin/umount
	KPARTX=/sbin/kpartx
	LVREMOVE=/sbin/lvremove
	LVDISPLAY=/sbin/lvdisplay
	LVCREATE=/sbin/lvcreate
	SSH=/usr/bin/ssh
	MYSQLDUMP=/usr/bin/mysqldump
	MKDIR=/bin/mkdir
	RM=/bin/rm
	TAR=/bin/tar
	MD5SUM=/usr/bin/md5sum
	GREP=/bin/grep
	AWK=/usr/bin/awk
	HEAD=/usr/bin/head
	CUT=/usr/bin/cut
	WC=/usr/bin/wc
	CAT=/bin/cat
	DU=/usr/bin/du
	SENDMAIL=/usr/sbin/sendmail
# Misc
	lvm_limit_one=0
	snapshot_max_size=50
	ssh_params="-o StrictHostKeyChecking=no -T -i /root/creds/nuage.pem"
	ssh_known=/root/.ssh/known_hosts
	ubuntu_ami="ami-0000000b"
# Mail
	enable_mail_notification=1
	email_recipient="razique.mahroua@gmail.com"
# MySQL
	enable_mysql_dump=1
	mysql_backup_name="mysql-dump"
	mysql_server_dpkg_name="mysql-server"
	mysql_backup_user="backup"
	mysql_backup_pass="backup_pass"
# Date formats 
	startTime=`date '+%s'`
	dateMail=`date '+%d/%m at %H:%M:%S'`
	dateFile=`date '+%d_%m_%Y'`
	dateFileBefore=`date --date='1 week ago' '+%d_%m_%Y'`
# Paths
	email_tmp_file=/root/ebs_backup_status.tmp
	#backup_destination=/root/BACKUP/EBS-VOL
	backup_destination=/var/lib/glance/images/BACKUP/EBS-VOL
	mysql_backup_path=/home/mysql/backup
	mount_point=/mnt
# Messages
	mailnotifications_disabled="The mail notifications are disabled"
	mysqldump_disabled="The mysqldumps are disabled"
	mysql_not_instaled="mysql is not installed, nothing to dump"
	dir_exists="The directory already exists"
	nothing="Nothing to remove"

#### ---------------------------------------------- DO NOT EDIT AFTER THAT LINE ----------------------------------------------  #####
if [ ! -f $email_tmp_file ]; then
	touch $email_tmp_file
else
	$CAT /dev/null > $email_tmp_file
fi
echo -e "Backup Start Time - $dateMail" >> $email_tmp_file

# 1- Main functions

## Fetch volumes infos
function get_lvs () {
	if [ $lvm_limit_one -eq 0 ]; then
		$LVDISPLAY | $GREP "LV Name" | $AWK '{ print $3 }' 
	else	
		$LVDISPLAY | $GREP "LV Name" | $AWK '{ print $3 }' | $HEAD -1
	fi
}

function get_lvs_name () {
	echo $1 | $CUT -d "/" -f 4
}

function get_lvs_id () {
	echo $1 | $CUT -d "-" -f 3
}

## Mysql dumps
function mysql_backup () {
	euca-describe-instances | $GREP -v -e "RESERVATION" -e "i-0000009c" | while read line; do
		ip_address=`echo $line | cut -f 5 -d " "`
		ami=`echo $line | grep $ubuntu_ami | $WC -l`;
		
		if [ $ami -eq 1 ]; then
   	    	ssh_connect ubuntu
		else
	   	    ssh_connect root
   	    fi
	done
}

function ssh_connect () {
	$CAT /dev/null > $ssh_known 
	
	$SSH $ssh_params $1@$ip_address <<-EOF
		if [ `dpkg -l | $GREP $mysql_server_dpkg_name | $WC -l` -eq 0 ]; then
			echo $mysql_not_instaled;
		else
			# Dump directory creation
			if [ ! -d $mysql_backup_path ]; then
				$MKDIR $mysql_backup_path
			else
				echo $dir_exists;
			fi

			# Dump creation
			$MYSQLDUMP --all-databases -u $mysql_backup_user -p$mysql_backup_pass > $mysql_backup_path/$mysql_backup_name-$dateFile.sql;

			# Old dumps deletion
			if [ -f $mysql_backup_path/$mysql_backup_name-$dateFileBefore ]; then
				rm $mysql_backup_path/$mysql_backup_name-$dateFileBefore.sql
			else
				echo $nothing;
			fi
		fi
		exit
	EOF
}

function time_accounting () {
	timeDiff=$(( $1 - $2 ))
	hours=$(($timeDiff / 3600))
	seconds=$(($timeDiff % 3600))
	minutes=$(($timeDiff / 60))
	seconds=$(($timeDiff % 60))
}

# 2- Snapshot creation
function create_snapshot () {
	$LVCREATE --size $3G --snapshot --name $1-SNAPSHOT $2;
}

# 3- File and applications backups
function create_tar () {
	if [ -d $backup_destination/$2 ]; then
		echo $dir_exists;
	else
		$MKDIR $backup_destination/$2;
	fi
		cd $backup_destination/$2
		$TAR --exclude={"lost+found","mysql/data","mysql/tmp"} -czf $2_$dateFile.tar.gz -C $mount_point . 
		$MD5SUM $backup_destination/$2/$2_$dateFile.tar.gz > $backup_destination/$2/$2_$dateFile.checksum
	
	if [ -f $backup_destination/$2_$dateFileBefore.tar ]; then
		# Rotation des anciens fichiers 
		$RM $backup_destination/$2_$dateFileBefore.tar;
		$RM $backup_destination/$2_$dateFileBefore.checksum;
	else 
		echo $nothing;
	fi
}

# 4- Databases backup
if [ $enable_mysql_dump -eq 0 ]; then
	echo $mysqldump_disabled
else
	mysql_backup
fi

# 5-Iteration through LVM volumes
for i in `get_lvs`; do
	startTimeLVM=`date '+%s'`
	
	echo -e "\n ######################### `get_lvs_name $i` #########################"
   
   	# Volumes retrieval
   	echo -e "\n STEP 1 :Snapshot creation"
   	create_snapshot `get_lvs_name $i` $i $snapshot_max_size 
	
   	echo -e "\n STEP 2 : Table partition creation"
   	$KPARTX -av $i-SNAPSHOT
	
   	echo -e "\n STEP 3 : Volumes mounting"
   	sleep 1;
	$MOUNT "/dev/mapper/nova--volumes-volume--`get_lvs_id $i`--SNAPSHOT1" $mount_point
	
   	echo -e "\n STEP 4 : Archive creation"
   	create_tar $i `get_lvs_name $i`
   
   	echo -e "\n STEP 5 : Umount volume"
   	$UMOUNT $mount_point
   
   	echo -e "\n STEP 6 : Table partition remove"
   	$KPARTX -d $i-SNAPSHOT
   
   	echo -e "\n STEP 7 : Snapshot deletion "
	sleep 1;
   	$LVREMOVE -f $i-SNAPSHOT

	#Time accounting per volume
	time_accounting `date '+%s'` $startTimeLVM
	
	# Mail notification creation
	backup_size=`$DU -h $backup_destination/\`get_lvs_name $i\` | $CUT -f 1`
	echo -e "$i - $hours h $minutes m and $seconds seconds. Size - $backup_size" >> $email_tmp_file	
done

# 6- Mail notification
if [ $enable_mail_notification -eq 0 ]; then
	echo $mailnotifications_disabled
else
	time_accounting `date '+%s'` $startTime
	echo -e "---------------------------------------" >> $email_tmp_file
	echo -e "Total backups size - `$DU -sh $backup_destination | $CUT -f 1`" >> $email_tmp_file
	echo -e "Total execution time - $hours h $minutes m and $seconds seconds" >> $email_tmp_file
	echo -e "To : $recipient \nSubject : The EBS volumes have been backed up in $hours h and $minutes mn the $dateMail \n`$CAT $email_tmp_file`" | $SENDMAIL $email_recipient
fi

rm $email_tmp_file
