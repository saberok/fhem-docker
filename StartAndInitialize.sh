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


### Functions to start FHEM ###

function StartFHEM {
#set -x
	LOGFILE=`date +'/opt/fhem/log/fhem-%Y-%m.log'`
	PIDFILE=/opt/fhem/log/fhem.pid 
	SLEEPINTERVAL=0.5
	
	## Function to print FHEM log in incremental steps to the docker log.
	OLDLINES=`wc -l < $LOGFILE`
	function PrintNewLines {
		LINES=`wc -l < $LOGFILE`
		tail -n `expr $LINES - $OLDLINES` $LOGFILE
		OLDLINES=$LINES
	}
	
	## Start FHEM
	echo
	echo 'Starting FHEM:'
	echo
	cd /opt/fhem
	trap "StopFHEM" SIGTERM
	perl fhem.pl fhem.cfg
	#while [ ! -e $PIDFILE ]; do
	#	sleep $SLEEPINTERVAL
	#done
	( tail -f -n0 $LOGFILE & ) | grep -q 'Server started'					## Wait for FHEM tp start up 
	
	## Evetually update FHEM
	if [ $UPDATE -eq 1 ]; then
		PrintNewLines
		echo
		echo 'Performing initial update of FHEM, this may take a minute...'
		echo
		perl /opt/fhem/fhem.pl 7072 update
		( tail -f -n0 $LOGFILE & ) | grep -q 'update finished'				## Wait for update to finish
		PrintNewLines
		echo
		echo 'Restarting FHEM after initial update...'
		echo
		perl /opt/fhem/fhem.pl 7072 "shutdown restart"
		( tail -f -n0 $LOGFILE & ) | grep -q 'Server started'				## Wait for FHEM tp start up
		#PID=`cat $PIDFILE`
		#while [ ! -d /proc/`cat $PIDFILE` ] || [ $PID -eq `cat $PIDFILE` ]; do
		#	sleep $SLEEPINTERVAL
		#done
		PrintNewLines
		echo
		echo 'FHEM updated and restarted!'
		echo 'FHEM is up and running now:'
		echo
	fi
	
	## Monitor FHEM during runtime
	while true; do 
		if [ ! -e $PIDFILE ]; then							## FHEM is running
			COUNTDOWN=10
			echo
			echo "FHEM process terminated unexpectedly, waiting for $COUNTDOWN seconds before stopping container..."
			sleep 1
			while [ ! -d /proc/`cat $PIDFILE` ] && [ $COUNTDOWN -gt 0 ]; do		## FHEM exited unexpectedly
				echo "waiting - $COUNTDOWN"
				let COUNTDOWN--
				sleep 1
			done
			if [ ! -d /proc/`cat $PIDFILE` ]; then					## FHEM didn't reappeared
				echo
				echo '0 - Stopping Container. Bye!'
				exit 1
			else									## FHEM reappeared
				echo
				echo 'FHEM process reappeared, kept container alive!'
				sleep $SLEEPINTERVAL
			fi
			echo
			echo 'FHEM is up and running again:'
			echo
			
		fi
		PrintNewLines									## Printing log lines in intervalls
		sleep $SLEEPINTERVAL
	done
#set +x
}


### Docker stop sinal handler ###

function StopFHEM {								##############
	echo
	echo 'SIGTERM signal received, sending "shutdown" command to FHEM!'
	echo
	cd /opt/fhem
	perl fhem.pl 7072 shutdown
	echo 'Waiting for FHEM process to terminate before stopping container:'
	( tail -f -n0 $LOGFILE & ) | grep -q 'Server shutdown'					## Wait for FHEM stop
	while [ -e $PIDFILE ]; do
		let COUNTUP++
		echo "waiting - $COUNTUP"
		sleep 1
	done
	echo 'FHEM process terminated, stopping container. Bye!'
	sleep 1
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
