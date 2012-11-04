#!/bin/bash

# Copyright 2012 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

# make sure needed directories exists
for directory in  /srv/jenkins /chroots ; do
	if [ ! -d $directory ] ; then
		sudo mkdir $directory
		sudo chown jenkins.jenkins $directory
	fi
done

#
# install the heart of jenkins.debian.net
#
cp -r bin logparse job-cfg /srv/jenkins/
cp -r userContent/* /var/lib/jenkins/userContent/
asciidoc -a numbered -a data-uri -a iconsdir=/etc/asciidoc/images/icons -a scriptsdir=/etc/asciidoc/javascripts -a imagesdir=./  -b html5 -a toc -a toclevels=4 -a icons -o about.html TODO && cp about.html /var/lib/jenkins/userContent/ && echo Updated about.html

#
# install packages we need
# (more or less grouped into more-then-nice-to-have, needed-while-things-are-new, needed)
#
sudo apt-get install vim screen less etckeeper curl mtr-tiny dstat devscripts bash-completion shorewall shorewall6 cron-apt apt-listchanges munin \
	build-essential python-setuptools \
	debootstrap sudo figlet graphviz apache2 python-yaml python-pip mr subversion subversion-tools vnstat

#
# deploy package configuration in /etc
#
sudo cp -r etc/* /etc

#
# more configuration than a simple cp can do
#
if [ ! -e /etc/apache2/mods-enabled/proxy.load ] ; then
	sudo a2enmod proxy
	sudo a2enmod proxy_http
fi
sudo chown root.root /etc/sudoers.d/jenkins ; sudo chmod 700 /etc/sudoers.d/jenkins
sudo ln -sf /etc/apache2/sites-available/jenkins.debian.net /etc/apache2/sites-enabled/000-default
sudo service apache2 reload
cd /etc/munin/plugins ; sudo rm -f postfix_* open_inodes df_inode interrupts diskstats irqstats threads proc_pri vmstat 2>/dev/null
[ -L apache_accesses ] || for i in apache_accesses apache_processes apache_volume ; do ln -s /usr/share/munin/plugins/cpu/$i $i ; done

#
# run jenkins-job-builder to update jobs if needed
#     (using sudo because /etc/jenkins_jobs is root:root 700)
#
cd /srv/jenkins/job-cfg 
sudo jenkins-jobs update .

