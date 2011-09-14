#!/bin/bash
# Shell : Bash
# Description : Qemu backing images prunning for nova-compute
# Author : razique.mahroua@gmail.com
# Actual version : Version 00

# 		Revision note    
# V00 : Initial version

#  		Notes    	
# This script allows an openstack administrator to purge the compute node for old or unused images
# See  : https://answers.launchpad.net/nova/+question/162498
	
# 		Usage
# chmod +x SCR_5008_$version_NUAC-Nova-compute-images-prunning.sh
# ./SCR_5008_$version_NUAC-Nova-compute-images-prunning.sh     

# Binaries
	RM=/bin/rm
	GREP=/bin/grep
	CUT=/usr/bin/cut
	WC=/usr/bin/wc
# Paths
	nova_instances_base_dir=/var/lib/nova/instances

find $nova_instances_base_dir -name disk* | xargs -n1 qemu-img info | grep backing | while read line; do
	image=`echo $line | $CUT -f 13 -d "/" | $CUT -f 1 -d ")"`
	cached_image=`ls -al $nova_instances_base_dir/_base | $GREP $image | wc -l`

	if [ $cached_image -gt 1 ]; then
		echo "$image is actually being used, cannot remove it !"
	else
		echo "$image can safely be removed." 
	fi
done
