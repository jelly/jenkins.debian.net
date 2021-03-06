#!/bin/bash

# Copyright 2015 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

#
# configure mock for a given release and architecture
#

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

if [ -z "$1" ] || [ -z "$2" ] ; then
	echo "Need release and architecture as params."
	exit 1
fi
RELEASE=$1
ARCH=$2

echo "$(date -u) - showing setup."
dpkg -l mock
id
echo "$(date -u) - cleaning ~/.rpmdb"
rm ~/.rpmdb -rf
echo "$(date -u) - cleaning yum"
yum -v --releasever=23 clean all
echo "$(date -u) - initialising yum for $RELEASE"
yum -v --releasever=23 check
yum -v --releasever=23 repolist all

for i in 1 2 ; do
	UNIQUEEXT="mock_$i"
	echo "$(date -u) - starting to cleanly configure mock for $RELEASE on $ARCH using unique extension $UNIQUEEXT."
	echo "$(date -u) - mock --clean"
	mock -r $RELEASE-$ARCH --uniqueext=$UNIQUEEXT --resultdir=. -v --clean
	echo "$(date -u) - mock --scrub=all"
	mock -r $RELEASE-$ARCH --uniqueext=$UNIQUEEXT --resultdir=. -v --scrub=all
	echo "$(date -u) - mock --init"
	mock -r $RELEASE-$ARCH --uniqueext=$UNIQUEEXT --resultdir=. -v --init
	echo "$(date -u) - mock --install rpm-build yum"
	mock -r $RELEASE-$ARCH --uniqueext=$UNIQUEEXT --resultdir=. -v --install rpm-build yum
	echo "$(date -u) - mock --update"
	mock -r $RELEASE-$ARCH --uniqueext=$UNIQUEEXT --resultdir=. -v --update
done

# finally
echo "$(date -u) - mock configured for $RELEASE on $ARCH."
