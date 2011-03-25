#!/bin/bash
# Distributed under the terms of the BSD License.
# Copyright (c) 2011 Phil Cryer phil.cryer@gmail.com
# Source https://github.com/philcryer/lipsync
 
clear
stty erase '^?'
echo "lipsync install script"

########################################
# Check users's privileges
########################################
echo -n "* Checking user's privileges..."
if [ "$(id -u)" != "0" ]; then 
	sudo -v >/dev/null 2>&1 || { echo; echo "	ERROR: User $(whoami) is not root, and does not have sudo privileges" ; exit 1; }
else
	echo "ok"
fi

########################################
# Check Linux variant
########################################
echo -n "* Checking Linux variant..."
if [ `cat /etc/issue.net | cut -d' ' -f1` == "Debian" ] || [ `cat /etc/issue.net | cut -d' ' -f1` == "Ubuntu" ];then
	echo "ok"
else
	echo; echo "	ERROR: this installer was written to work with Debian/Ubuntu,"
	echo       "	it could work (tm) with your system - let us know if it does"
fi

########################################
# Check for required software
########################################
echo -n "* Checking for required software..."
type -P ssh &>/dev/null || { echo; echo "	ERROR: lipsync requires ssh-client but it's not installed" >&2; exit 1; }
type -P ssh-copy-id &>/dev/null || { echo; echo "	ERROR: lipsync requires ssh-copy-id but it's not installed" >&2; exit 1; }
type -P rsync &>/dev/null || { echo; echo "	ERROR: lipsync requires rsync but it's not installed" >&2; exit 1; }
type -P lsyncd &>/dev/null || { echo; echo "	ERROR: lipsync requires lsyncd but it's not installed" >&2; exit 1; }
echo "ok"

########################################
# Define functions
########################################
questions(){
	echo -n "> SERVER: IP or domainname: "
	read remote_server

	echo -n "> SERVER: SSH port: "
	read port
	
	echo -n "> SERVER/CLIENT: username (must exist on both): "
    	read username
    
	echo -n "> CLIENT: directory to be synced: "
	read lipsync_dir_local

	echo -n "> SERVER: remote directory to be synced: "
	read lipsync_dir_remote
}

ssh.keygen(){
	if [ -f '/home/${username}/.ssh/id_dsa' ]; then
		echo "* Existing SSH key found for ${username} backing up..."
		mv /home/${username}/.ssh/id_dsa /home/${username}/.ssh/id_dsa-OLD
		if [ $? -eq 0 ]; then
			echo "done"
		else
			echo; echo "	ERROR: there was an error backing up the SSH key"; exit 1
		fi
	fi
	echo -n "* Creating new SSH key for ${username}..."
	ssh-keygen -q -N '' -f /home/${username}/.ssh/id_dsa
	if [ $? -eq 0 ]; then
		chown -R $username:$username /home/${username}/.ssh
		echo "done"
	else
		echo; echo "	ERROR: there was an error generating the ssh key"; exit 1
	fi
	
	echo "* Transferring ssh key for ${username} to ${remote_server} on port ${port} (login as $username now)..."; 
	su ${username} -c "ssh-copy-id -i /home/${username}/.ssh/id_dsa.pub '-p ${port} ${username}@${remote_server}'" >> /dev/null

	if [ $? -eq 0 ]; then
		X=0	#echo "done"
	else
		echo; echo "	ERROR: there was an error transferring the ssh key"; exit 1
	fi
	echo -n "* Setting permissions on the ssh key for ${username} on ${remote_server} on port ${port}..."; 
	su ${username} -c "SSH_AUTH_SOCK=0 ssh ${remote_server} -p ${port} 'chmod 700 .ssh'"
	if [ $? -eq 0 ]; then
		echo "done"
	else
		echo; echo "	ERROR: there was an error setting permissions on the ssh key for ${username} on ${remote_server} on port ${port}..."; exit 1
	fi
}

build.conf(){
	echo -n "* Creating lipsyncd config..."
	sed 's|LSLOCDIR|'$lipsync_dir_local/'|g' etc/lipsyncd > /tmp/lipsyncd01 
	sed 's|LSUSER|'$username'|g' /tmp/lipsyncd01 > /tmp/lipsyncd02
	sed 's|LSPORT|'$port'|g' /tmp/lipsyncd02 > /tmp/lipsyncd03
	sed 's|LSREMSERV|'$remote_server'|g' /tmp/lipsyncd03 > /tmp/lipsyncd04
	sed 's|LSREMDIR|'$lipsync_dir_remote'|g' /tmp/lipsyncd04 > /tmp/lipsyncd
	echo "done"
}

deploy(){
	echo "* Deploying lipsync..."
	echo -n "	> /usr/local/bin/lipsync..."
	cp bin/lipsync /usr/local/bin; chown root:root /usr/local/bin/lipsync; chmod 755 /usr/local/bin/lipsync
	echo "done"

	echo -n "	> /usr/local/bin/lipsyncd..."
	ln -s /usr/local/bin/lsyncd /usr/local/bin/lipsyncd
	echo "done"

	echo -n "	> /etc/init.d/lipsyncd..."
	cp etc/init.d/lipsyncd /etc/init.d
	echo "done"

	echo -n "	> /etc/cron.d/lipsync..."
	cp etc/cron.d/lipsync /etc/cron.d
	echo "done"

	echo -n "	> /etc/lipsyncd..."
	mv /tmp/lipsyncd /etc/
	echo "done"

	echo -n "	> /usr/share/doc/lipsyncd..."
	if [! -d '/usr/share/doc/lipsyncd' ]; then
		mkdir /usr/share/doc/lipsyncd
	fi
	cp README* INSTALL* LICENSE uninstall.sh doc/* /usr/share/doc/lipsyncd
	echo "done"

	echo -n "	> /var/log/lipsyncd.log..."
	touch /var/log/lipsyncd.log
	chmod g+w /var/log/lipsyncd.log
	echo "done"

	echo "lipsync installed `date`" > /var/log/lipsyncd.log
}

start(){
	/etc/init.d/lipsyncd start; sleep 2
	if [ -f /var/run/lipsyncd.pid ]; then
		echo "	NOTICE: lipsyncd is running as pid `cat /var/run/lipsyncd.pid`"
		echo "	Check /var/log/lipsyncd.log for details"
	else
		echo "	NOTICE: lipsyncd failed to start..."
		echo "	Check /var/log/lipsyncd.log for details"
	fi
}

########################################
# Install lipsyncd 
########################################
if [ "${1}" = "uninstall" ]; then
	echo "	ALERT: Uninstall option chosen, all lipsync files and configuration will be purged!"
	echo -n "	ALERT: To continue press enter to continue, otherwise hit ctrl-c now to bail..."
	read continue
	uninstall
	exit 0
else
	questions
	ssh.keygen
	build.conf
	deploy
fi

########################################
# Start lipsyncd
########################################
echo "lipsync setup complete, starting lipsyncd..."
start

exit 0
