#!/bin/bash
##################################################################################################
##
##	Start and intitialization script for fhem-docker
##	Copyright (c) 2018 Joscha Middendorf
##
##	Before mounting a volume to the container, this script comresses the content 
##	of a provided configuration directory to /root/_config.
##	usage:	./StartAndInitialize.sh Arg1=initialize Arg2=/abs/path/to/directory/
##
##	After mounting a volume to the container, this script extracts the content 
##	of the previously compressed configuration directory back to a provided directory,
##	if the directory is empty.
##	usage:	./StartAndInitialize.sh Arg1=extract Arg2=/abs/path/to/directory/
##
##################################################################################################

## turn on Debugging
#set -x


### Functions to start FHEM ###

function StartFHEM {
	LOGFILE=`date +'/opt/fhem/log/fhem-%Y-%m.log'`
	PIDFILE=/opt/fhem/log/fhem.pid 
	OLDLINES=`wc -l < $LOGFILE`
	
	echo
	echo 'Starting FHEM:'
	echo
	cd /opt/fhem
	trap "StopFHEM" SIGTERM SIGINT
	perl fhem.pl fhem.cfg
	while [ ! -e $PIDFILE ]; do
		sleep 0.1
	done
set -x
	if [ $UPDATE -eq 1 ]; then
		echo 'Performing initial update of FHEM...'
		sleep 2
		PID=`cat $PIDFILE`
		#perl /opt/fhem/fhem.pl 7072 update
		sleep 5
		#perl /opt/fhem/fhem.pl 7072 "shutdown restart"
		while [ ! -e $PIDFILE ] || [ $PID==`cat $PIDFILE` ]; do
			sleep 10
		done
		echo
		echo 'FHEM updated and restarted!'
		echo
	fi
set +x
	while true; do 
		if [ ! -e $PIDFILE ]; then
			COUNTDOWN=10
			echo
			echo "FHEM process terminated, waiting for $COUNTDOWN seconds before stopping container:"
			while [ ! -e $PIDFILE ] && [ $COUNTDOWN -gt 0 ]; do
				sleep 1
				echo "waiting - $COUNTDOWN"
				let COUNTDOWN--
			done
			sleep 1
			if [ ! -e $PIDFILE ]; then
				echo '0 - Stopping Container. Bye!'
				exit 1
			else
				echo 'FHEM process reappeared, container still running:'
			fi
			echo
			echo 'FHEM:'
			echo
		fi
		LINES=`wc -l < $LOGFILE`
		tail -n `expr $LINES - $OLDLINES` $LOGFILE
		OLDLINES=$LINES
		sleep 0.1
	done
}


### Docker stop sinal handler ###

function StopFHEM {
	echo
	echo 'SIGTERM signal received, sending "shutdown" command to FHEM!'
	echo
	cd /opt/fhem
	perl fhem.pl 7072 shutdown
	echo 'Waiting for FHEM process to terminate before stopping container:'
	while [ -e $PIDFILE ]; do
		let COUNTUP++
		echo "waiting - $COUNTUP"
		sleep 1
	done
	echo 'FHEM process terminated, stopping container. Bye!'
	exit 0
}


### Start of Script ###

echo 
echo '-------------------------------------------------------------------------------------------------------------------------'
if [ -z $2 ]; then
    echo 'Error: Not enough arguments provided, please provide Arg1=initialize/extract and Arg2=/abs/path/to/directory/'
    exit 1
fi

PACKAGEDIR=/root/_config
test -e $PACKAGEDIR || mkdir -p $PACKAGEDIR 

case $1 in
	initialize)
		echo 'Creating package of /opt/fhem/:'
		echo 
		## check if $2 is a extsting directory
		if  [ -d  $2 ]; then  
			PACKAGE=$PACKAGEDIR/`echo $2 | tr '[/]' '-'`.tgz
			tar -czf $PACKAGE $2
			echo "Created package $PACKAGE from $2."
		fi
		;;
	extract)
		echo 'Extracting config data to /opt/fhem/ if empty:'
		echo 
		## check if $PACKAGE was extracted before
		PACKAGE=$PACKAGEDIR/`echo $2 | tr '[/]' '-'`.tgz
		if [ -e $PACKAGE.extracted ]; then
			echo "The package $PACKAGE was already extracted before, no extraction processed!"
			UPDATE=0
			StartFHEM
		fi
		
		# check if directory $2 is empty
		if 	[ "$(ls -A $2)" ]; then
			echo "Directory $2 isn't empty, no extraction processed!"
			UPDATE=0
			StartFHEM
		else 
			# check if $PACKAGE exists
			if [ -e $PACKAGE ]; then
				tar -xzkf $PACKAGE -C / 
				touch $PACKAGE.extracted
				echo "Extracted package $PACKAGE to $2 to initialize the configuration directory."
				UPDATE=1 
				StartFHEM
			fi
		fi	
		;;
	*)
		echo 'Error: Wrong arguments provided, please provide Arg1=initialize/extract and Arg2=/abs/path/to/directory/'
		exit 1
	;;
esac
