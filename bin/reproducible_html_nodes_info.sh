#!/bin/bash
# vim: set noexpandtab:

# Copyright © 2015-2018 Holger Levsen <holger@layer-acht.org>
#           ©      2018 Mattia Rizzolo <mattia@debian.org>
# released under the GPLv=2

set -e

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code defining db access
. /srv/jenkins/bin/reproducible_common.sh

TARGET_DIR=/srv/reproducible-results/node-information/
mkdir -p $TARGET_DIR
TMPFILE_SRC=$(mktemp)
TMPFILE_NODE=$(mktemp)
# remove old node entries which are older than two weeks
find $TARGET_DIR/ -type f -mtime +14 -exec rm -v {} \;

#
# build static webpages
#
VIEW=nodes_health
PAGE=index_${VIEW}.html
ARCH=amd64
SUITE=unstable
echo "$(date -u) - starting to write $PAGE page."
write_page_header $VIEW "Nodes health overview"
DISCLAIMER="<p>This page is still under development. Please provide feedback, which other information (be it from munin or elsewhere) should be displayed and how this page should be split further, eg, the graphs could all be on another page and/or we should split this page into four for the four architectures being tested…</p>"
write_page "$DISCLAIMER"
write_page "<p style=\"clear:both;\">"
for ARCH in ${ARCHS} ; do
	write_page "<h3>$ARCH nodes</h3>"
	write_page "<table>"
	write_page "<tr><th>Name</th><th>health check</th><th>maintenance</th><th>Debian worker.log links</th>"
		for SUITE in ${SUITES} ; do
			write_page "<th>pbuilder setup $SUITE</th>"
		done
		for SUITE in ${SUITES} ; do
			if [ "$SUITE" == "experimental" ]; then
				continue
			fi
			write_page "<th>schroot setup $SUITE</th>"
		done
	write_page "</tr>"
	# the following for-loop is a hack to insert nodes which are not part of the
	# Debian Reproducible Builds node network but are using for reproducible builds
	# tests of other projects…
	REPRODUCIBLE_NODES="jenkins"

	for NODE in $BUILD_NODES ; do
		REPRODUCIBLE_NODES="$REPRODUCIBLE_NODES $NODE"
		if [ "$NODE" = "profitbricks-build2-i386.debian.net" ] ; then
			REPRODUCIBLE_NODES="$REPRODUCIBLE_NODES profitbricks-build3-amd64.debian.net profitbricks-build4-amd64.debian.net profitbricks-build7-amd64.debian.net"
		fi
	done
	for NODE in $REPRODUCIBLE_NODES ; do
		if [ -z "$(echo $NODE | grep $ARCH || true)" ] && [ "$NODE" != "jenkins" ] ; then
			continue
		elif [ "$NODE" = "jenkins" ] && [ "$ARCH" != "amd64" ] ; then
			continue
		fi
		if [ "$NODE" = "jenkins" ] ; then
			JENKINS_NODENAME=jenkins
			NODE="jenkins.debian.net"
		else
			case $ARCH in
				amd64|i386) 	JENKINS_NODENAME=$(echo $NODE | cut -d "-" -f1-2|sed 's#-build##' ) ;;
				arm64) 		JENKINS_NODENAME=$(echo $NODE | cut -d "-" -f1-2|sed 's#-sled##' ) ;;
				armhf) 		JENKINS_NODENAME=$(echo $NODE | cut -d "-" -f1) ;;
			esac
		fi
		write_page "<tr><td>$JENKINS_NODENAME"
		# mark offline nodes
		if [ -f "$JENKINS_OFFLINE_LIST" ]; then
			if grep -q "$NODE" "$JENKINS_OFFLINE_LIST"; then
				write_page '</td><td colspan="11" style="text-align: center;"><span style="font-style: italic;">offline</span></td>'
				continue
			fi
		fi
		write_page "</td>"
		# health check
		URL="https://jenkins.debian.net/view/reproducible/view/Node_maintenance/job/reproducible_node_health_check_${ARCH}_${JENKINS_NODENAME}"
		BADGE="$URL/badge/icon"
		write_page "<td><a href='$URL'><img src='$BADGE' /></a></td>"
		# maintenance
		URL="https://jenkins.debian.net/view/reproducible/view/Node_maintenance/job/reproducible_maintenance_${ARCH}_${JENKINS_NODENAME}"
		BADGE="$URL/badge/icon"
		write_page "<td><a href='$URL'><img src='$BADGE' /></a></td>"
		# worker.log links
		case $JENKINS_NODENAME in
			jenkins)	write_page "<td></td>" ;;
			profitbricks3)	write_page "<td></td>" ;;
			profitbricks4)	write_page "<td></td>" ;;
			profitbricks7)	write_page "<td></td>" ;;
			*)		write_page "<td>"
					SHORTNAME=$(echo $NODE | cut -d '.' -f1)
					for WORKER in $(grep "${ARCH}_" /srv/jenkins/bin/reproducible_build_service.sh | grep -v \# |grep $SHORTNAME | cut -d ')' -f1) ; do
						write_page "<a href='https://jenkins.debian.net/userContent/reproducible/debian/build_service/${WORKER}/worker.log'>"
						write_page "$(echo $WORKER |cut -d '_' -f2)</a> "
					done
					write_page "</td>"
					;;
		esac
		# pbuilder setup
		for SUITE in ${SUITES} ; do
			case $JENKINS_NODENAME in
				jenkins)	write_page "<td></td>" ;;
				profitbricks3)	write_page "<td></td>" ;;
				profitbricks4)	write_page "<td></td>" ;;
				profitbricks7)	write_page "<td></td>" ;;
				*)		URL="https://jenkins.debian.net/view/reproducible/view/Debian_setup_${ARCH}/job/reproducible_setup_pbuilder_${SUITE}_${ARCH}_${JENKINS_NODENAME}"
						BADGE="$URL/badge/icon"
						write_page "<td><a href='$URL'><img src='$BADGE' /></a></td>"
						;;
			esac
		done
		# diffoscope schroot setup
		for SUITE in ${SUITES} ; do
			if [ "$SUITE" == "experimental" ]; then
				continue
			fi
			URL="https://jenkins.debian.net/view/reproducible/view/Debian_setup_${ARCH}/job/reproducible_setup_schroot_${SUITE}_diffoscope_${ARCH}_${JENKINS_NODENAME}"
			BADGE="$URL/badge/icon"
			case $JENKINS_NODENAME in
				profitbricks3)
					if [ "$SUITE" = "unstable" ]; then
						write_page "<td><a href='$URL'><img src='$BADGE' /></a></td>"
					else
						write_page "<td></td>"
					fi
					;;
				jenkins)
					write_page "<td><a href='$URL'><img src='$BADGE' /></a></td>"
					;;
				*) write_page "<td></td>" ;;
			esac
		done
		write_page "</tr>"
	done
	write_page "</table>"
done
write_page "</p>"
write_page_footer
publish_page debian

for TYPE in daily weekly ; do
	VIEW=nodes_${TYPE}_graphs
	PAGE=index_${VIEW}.html
	ARCH=amd64
	SUITE=unstable
	echo "$(date -u) - starting to write $PAGE page."
	write_page_header $VIEW "Nodes $TYPE graphs"
	write_page "$DISCLAIMER"
	write_page "<p style=\"clear:both;\">"
	for ARCH in ${ARCHS} ; do
		write_page "<h3>$ARCH nodes</h3>"
		write_page "<table>"
		write_page "<tr><th>Name</th><th colspan='6'></th>"
		write_page "</tr>"
		for NODE in $REPRODUCIBLE_NODES ; do
			if [ -z "$(echo $NODE | grep $ARCH || true)" ] && [ "$NODE" != "jenkins" ] ; then
				continue
			elif [ "$NODE" = "jenkins" ] && [ "$ARCH" != "amd64" ] ; then
				continue
			fi
			if [ "$NODE" = "jenkins" ] ; then
				JENKINS_NODENAME=jenkins
				NODE="jenkins.debian.net"
			else
				case $ARCH in
					amd64|i386) 	JENKINS_NODENAME=$(echo $NODE | cut -d "-" -f1-2|sed 's#-build##' ) ;;
					arm64) 		JENKINS_NODENAME=$(echo $NODE | cut -d "-" -f1-2|sed 's#-sled##' ) ;;
					armhf) 		JENKINS_NODENAME=$(echo $NODE | cut -d "-" -f1) ;;
				esac
			fi
			write_page "<tr><td>$JENKINS_NODENAME</td>"
			for GRAPH in jenkins_reproducible_builds cpu memory df swap load ; do
				if [ "$GRAPH" = "jenkins_reproducible_builds" ] ; then
					case $JENKINS_NODENAME in
						jenkins)	write_page "<td></td>" ; continue ;;
						profitbricks3)	write_page "<td></td>" ; continue ;;
						profitbricks4)	write_page "<td></td>" ; continue ;;
						profitbricks7)	write_page "<td></td>" ; continue ;;
						*)		;;
					esac
				fi
				write_page "<td><a href='https://jenkins.debian.net/munin/debian.net/$NODE/$GRAPH.html'>"
				if [ "$TYPE" = "daily" ] ; then
					IMG=day.png
				else
					IMG=week.png
				fi
				write_page "<img src='https://jenkins.debian.net/munin/debian.net/$NODE/${GRAPH}-${IMG}' width='150' /></a></td>"
			done
			write_page "</tr>"
			
		done
		write_page "</table>"
	done
	write_page "</p>"
	write_page_footer
	publish_page debian
done

#
# collect node information
#
echo "$(date -u) - Collecting information from nodes"
for NODE in $BUILD_NODES jenkins.debian.net ; do
	if [ "$NODE" = "jenkins.debian.net" ] ; then
		echo "$(date -u) - Trying to update $TARGET_DIR/$NODE."
		/srv/jenkins/bin/reproducible_info.sh > $TARGET_DIR/$NODE
		echo "$(date -u) - $TARGET_DIR/$NODE updated:"
		cat $TARGET_DIR/$NODE
		continue
	fi
	# call jenkins_master_wrapper.sh so we only need to track different ssh ports in one place
	# jenkins_master_wrapper.sh needs NODE_NAME and JOB_NAME
	export NODE_NAME=$NODE
	export JOB_NAME=$JOB_NAME
	echo "$(date -u) - Trying to update $TARGET_DIR/$NODE."
	set +e
	/srv/jenkins/bin/jenkins_master_wrapper.sh /srv/jenkins/bin/reproducible_info.sh > $TMPFILE_SRC
	if [ $? -eq 1 ] ; then
		echo "$(date -u) - Warning: could not update $TARGET_DIR/$NODE."
		continue
	fi
	set -e
	for KEY in $BUILD_ENV_VARS ; do
		VALUE=$(egrep "^$KEY=" $TMPFILE_SRC | cut -d "=" -f2-)
		if [ ! -z "$VALUE" ] ; then
			echo "$KEY=$VALUE" >> $TMPFILE_NODE
		fi
	done
	if [ -s $TMPFILE_NODE ] ; then
		mv $TMPFILE_NODE $TARGET_DIR/$NODE
		echo "$(date -u) - $TARGET_DIR/$NODE updated:"
		cat $TARGET_DIR/$NODE
	fi
	rm -f $TMPFILE_SRC $TMPFILE_NODE
done
echo

echo "$(date -u) - Showing node performance:"
TMPFILE1=$(mktemp)
TMPFILE2=$(mktemp)
TMPFILE3=$(mktemp)
NOW=$(date -u '+%Y-%m-%d %H:%m')
for i in $BUILD_NODES ; do
	query_db "SELECT build_date FROM stats_build AS r WHERE ( r.node1='$i' OR r.node2='$i' )" > $TMPFILE1 2>/dev/null
	j=$(wc -l $TMPFILE1|cut -d " " -f1)
	k=$(cat $TMPFILE1|cut -d " " -f1|sort -u|wc -l)
	l=$(echo "scale=1 ; ($j/$k)" | bc)
	echo "$l builds/day ($j/$k) on $i" >> $TMPFILE2
	DATE=$(date '+%Y-%m-%d %H:%M' -d "-1 days")
	m=$(query_db "SELECT count(build_date) FROM stats_build AS r WHERE ( r.node1='$i' OR r.node2='$i' ) AND r.build_date > '$DATE' " 2>/dev/null)
	if [ "$m" = "" ] ; then m=0 ; fi
	echo "$m builds in the last 24h on $i" >> $TMPFILE3
done
rm $TMPFILE1 >/dev/null
sort -g -r $TMPFILE2
echo
sort -g -r $TMPFILE3
rm $TMPFILE2 $TMPFILE3 >/dev/null
echo

