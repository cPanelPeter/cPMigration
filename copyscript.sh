#!/bin/bash
# Original version written by Phil Stark
# Maintained and updated by Phil Stark and Blaine Motsinger
#
VERSION="1.0.7"
#
# Purpose:  to find all accounts existing on the Source server that do not exist
# on the destination server, package and transfer those accounts,  and restore
# them on the Destination  server automatically.  This is intended to use either
# in lieu of the WHM tools or as a followup to manually  package accounts that
# otherwise failed in WHM "Copy multiple accounts ..."
#
# usage: run on destination server
# $ sh copyscript <sourceIP>
####################
# This script copies all accounts from the source server that do not exist
# on the destination server already.
# This should always be run on the destination server
# NOTE:  a RSA key should be set up Destination > Source before running
# this script for password-less login.
#############################################

#############################################
# functions
#############################################
print_intro() {
    echo 'copyscript'
    echo "version $VERSION"
}

print_help() {
    echo 'usage:'
    echo './copyscript -s sourceserver'
    echo
    echo 'required:' 
    echo '-s sourceserver (hostname or ip)'
    echo
    echo 'optional:'
    echo '-p sourceport'
    echo '-h displays this dialogue'
    echo;exit 1
}

#############################################
# get options
#############################################
while getopts ":s:p:h" opt;do
    case $opt in
        s) sourceserver="$OPTARG";;
        p) sourceport="$OPTARG";;
        h) print_help;;
       \?) echo "invalid option: -$OPTARG";echo;print_help;;
        :) echo "option -$OPTARG requires an argument.";echo;print_help;;
    esac
done

if [[ $# -eq 0 || -z $sourceserver ]];then print_help;fi  # check for existence of required var

#############################################
# initial checks
#############################################

# check for root
if [ $EUID -ne 0 ];then
    echo 'copyscript must be run as root'
    echo;exit 1
fi

# check for connection or resolving sourceserver
if [[ $sourceserver =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]];then  # if ip  [todo] fine tune regex; this improperly matches 999.255.255.0
    if [[ $(ping -c1 -w2 $sourceserver) =~ .*'64 bytes'.* ]];then echo 'connection is fine'  # [todo] this may be not necessary, or possibliy of expanding this whole section into a more vast connection check, using port
    else echo 'connection is broken'  # output for testing
    fi
    echo;exit  # exit for testing
elif [[ -z $(dig $sourceserver +short) ]];then
    echo "$sourceserver does not appear to be resolving"
    echo 'please check your variable, as well as resolv.conf'
    echo;exit 1
fi

#############################################
# options operators
#############################################

# Package accounts on the source server
pkgaccounts=1

# Restore packages on the destination server
restorepkg=1

# Delete cpmove files from the source once transferred to the destination server
removesourcepkgs=0

# Delete cpmove files from the destination server once restored
removedestpkgs=0

#############################################
### Pre-Processing
#############################################

# Make working directory
mkdir /root/.copyscript
mkdir /root/.copyscript/log

# Define epoch time
epoch=`date +%s`

# grab source accounts list
scp root@$sourceserver:/etc/trueuserdomains /root/.copyscript/.sourcetudomains

# sort source accounts list
sort /root/.copyscript/.sourcetudomains > /root/.copyscript/.sourcedomains

# grab and sort local (destination) accounts list
sort /etc/trueuserdomains > /root/.copyscript/.destdomains

# diff out the two lists,  parse out usernames only and remove whitespace.  Output to copyaccountlist :) 
diff -y /root/.copyscript/.sourcedomains /root/.copyscript/.destdomains | grep \< | awk -F':' '{ print $2 }' | sed -e 's/^[ \t]*//' | awk -F' ' '{ print $1 }' > /root/.copyscript/.copyaccountlist


#############################################
# Process loop
#############################################
i=1
count=`cat /root/.copyscript/.copyaccountlist | wc -l`
for user in `cat /root/.copyscript/.copyaccountlist`
do
progresspercent=`expr $i / $count` * 100 
		echo Processing account $user.  $i/$count \($progresspercent%\) > >(tee --append /root/.copyscript/log/$epoch.log)

		# Package accounts on source server (if set)
		if [ $pkgaccounts == 1 ]
			then
			ssh root@$sourceserver "/scripts/pkgacct $user;exit"	> >(tee --append /root/.copyscript/log/$epoch.log)
		fi

		# copy (scp) the cpmove file from the source to destination server
		scp root@$sourceserver:/home/cpmove-$user.tar.gz /home/ > >(tee --append /root/.copyscript/log/$epoch.log)

		# Remove cpmove from source server (if set)
		if [ $removesourcepkgs == 1 ]
			then
			ssh root@$sourceserver "rm -f /home/cpmove-$user.tar.gz ;exit"	 > >(tee --append /root/.copyscript/log/$epoch.log)
		fi

		# Restore package on the destination server (if set)
		if [ $restorepkg == 1 ]
			then
			/scripts/restorepkg /home/cpmove-$user.tar.gz  > >(tee --append /root/.copyscript/log/$epoch.log)
		fi

		# Remove cpmove from destination server (if set)
		if [ $removedestpkgs == 1 ]
			then
			rm -fv /home/cpmove-$user.tar.gz	  > >(tee --append /root/.copyscript/log/$epoch.log)
		fi		
		i=`expr $i + 1`
done
