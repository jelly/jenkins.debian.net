#!/bin/bash

# Copyright 2015-2017 Holger Levsen <holger@layer-acht.org>
# released under the GPLv=2

DEBUG=false
. /srv/jenkins/bin/common-functions.sh
common_init "$@"

# common code
. /srv/jenkins/bin/reproducible_common.sh

set -e

update_archlinux_repositories() {
	echo "$(date -u) - Updating Arch Linux repositories, currently $(find $BASE/archlinux/ -name pkg.needs_build | wc -l ) packages scheduled."
	UPDATED=$(mktemp -t archlinuxrb-scheduler-XXXXXXXX)
	NEW=$(mktemp -t archlinuxrb-scheduler-XXXXXXXX)
	OLDER=$(mktemp -t archlinuxrb-scheduler-XXXXXXXX)
	local SESSION="archlinux-scheduler-$RANDOM"
	schroot --begin-session --session-name=$SESSION -c jenkins-reproducible-archlinux
	schroot --run-session -c $SESSION --directory /var/tmp -- sudo pacman -Syu --noconfirm
	# Get a list of unique package bases.  Non-split packages don't have a pkgbase set
	# so we need to use the pkgname for them instead.
	schroot --run-session -c $SESSION --directory /var/tmp -- expac -S '%r %e %n %v' | \
		while read repo pkgbase pkgname version; do
			if [[ "$pkgbase" = "(null)" ]]; then
				printf '%s %s %s\n' "$repo" "$pkgname" "$version"
			else
				printf '%s %s %s\n' "$repo" "$pkgbase" "$version"
			fi
		done | sort -u -R > "$ARCHLINUX_PKGS"_full_pkgbase_list
	TOTAL=$(cat ${ARCHLINUX_PKGS}_full_pkgbase_list | wc -l)
	echo "$(date -u ) - $TOTAL Arch Linux packages are known in total to us."

	for REPO in $ARCHLINUX_REPOS ; do
		TMPPKGLIST=$(mktemp -t archlinuxrb-scheduler-XXXXXXXX)
		echo "$(date -u ) - updating list of available packages in repository '$REPO'."
		grep "^$REPO" "$ARCHLINUX_PKGS"_full_pkgbase_list | \
			while read repo pkgbase version; do
				if [ ! -d $BASE/archlinux/$REPO/$pkgbase ] ; then
					# schedule (all) entirely new packages
					echo $REPO/$pkgbase >> $NEW
					echo "$(date -u ) - scheduling new package $REPO/$pkgbase... "
					mkdir -p $BASE/archlinux/$REPO/$pkgbase
					touch $BASE/archlinux/$REPO/$pkgbase/pkg.needs_build
				elif [ ! -f $BASE/archlinux/$REPO/$pkgbase/pkg.needs_build ] ; then
					if [ -f $BASE/archlinux/$REPO/$pkgbase/pkg.version ] ; then
						VERSION=$(cat $BASE/archlinux/$REPO/$pkgbase/pkg.version 2>/dev/null)
						if [ "$VERSION" != "$version" ] ; then
							VERCMP="$(schroot --run-session -c $SESSION --directory /var/tmp -- vercmp $version $VERSION || true)"
							if [ "$VERCMP" = "1" ] ; then
								# schedule packages where an updated version is availble
								echo $REPO/$pkgbase >> $UPDATED
								echo "$(date -u ) - we know $REPO/$pkgbase $VERSION, but repo has $version, so rescheduling... "
								touch $BASE/archlinux/$REPO/$pkgbase/pkg.needs_build
							elif [ "$VERCMP" = "-1" ] ; then
								echo "$REPO/$pkgbase $VERSION > $version" >> $OLDER
							else
								echo "$(date -u ) - This should never happen: we know about $pkgbase $VERSION, but repo has $version. \$VERCMP=$VERCMP"
							fi
						fi
					else
						echo "$(date -u ) - scheduling new package $REPO/$pkgbase... though this is strange and should not really happen…"
						touch $BASE/archlinux/$REPO/$pkgbase/pkg.needs_build
					fi
				fi
				printf '%s %s\n' "$pkgbase" "$version" >> $TMPPKGLIST
			done
		mv $TMPPKGLIST "$ARCHLINUX_PKGS"_"$REPO"
		echo "$(date -u ) - $(cat ${ARCHLINUX_PKGS}_$REPO | wc -l) packages in repository '$REPO' are known to us."
		new=$(grep -c ^$REPO $NEW || true)
		updated=$(grep -c ^$REPO $UPDATED || true)
		echo "$(date -u ) - scheduled $new/$updated packages in repository '$REPO'."
	done
	schroot --end-session -c $SESSION
	echo "$(date -u) - the following packages are known to us with higher versions than the repo because we build trunk:"
	cat $OLDER
	# schedule up to $MAX packages we already know about
	# (only if less than $THRESHOLD packages are currently scheduled)
	# FIXME: this doesnt reschedule packages without build1.log, 
	# though there shouldnt be any.
	old=""
	local MAX=350
	local THRESHOLD=450
	if [ $(find $BASE/archlinux/ -name pkg.needs_build | wc -l ) -le $THRESHOLD ] ; then
		local BLACKLIST="/($(echo $ARCHLINUX_BLACKLISTED | sed "s# #|#g"))/"
		# reschedule
		find $BASE/archlinux/ -name build1.log -type f -printf '%T+ %p\n' | sort | egrep -v "$BLACKLIST" | head -n $MAX| cut -d " " -f2 | sed -s 's#build1.log$#pkg.needs_build#g' | xargs -r touch
		# explain, for debugging…
		find $BASE/archlinux/ -name build1.log -type f -printf '%T+ %p\n' | sort | egrep -v "$BLACKLIST" | head -n $MAX| cut -d "/" -f8-9 | sort > $OLDER
		if [ -s $OLDER ] ; then
			old=" $(cat $OLDER | wc -l) old ones"
			echo "$(date -u) - Old, previously tested packages rescheduled: "
			for REPO in $ARCHLINUX_REPOS ; do
				grep ^$REPO $OLDER | sed "s#^#  #g"
			done
		fi
	fi
	rm $OLDER
	total=$(find $BASE/archlinux/ -name pkg.needs_build | wc -l )
	rm "$ARCHLINUX_PKGS"_full_pkgbase_list
	new=$(cat $NEW | wc -l 2>/dev/null|| true)
	updated=$(cat $UPDATED 2>/dev/null| wc -l || true)
	if [ $new -ne 0 ] || [ $updated -ne 0 ] || [ -n "$old" ] ; then
		message="scheduled"
		if [ $new -ne 0 ] ; then
			message="$message $new entirely new packages"
		fi
		if [ $new -ne 0 ] && [ $updated -ne 0 ] ; then
			message="$message and"
		fi
		if [ $updated -ne 0 ] ; then
			message="$message $updated packages with newer versions"
		fi
		if [ -n "$old" ] && ( [ $new -ne 0 ] || [ $updated -ne 0 ] ) ; then
			old=", plus$old"
		fi
		irc_message archlinux-reproducible "${message}$old, for $total scheduled out of $TOTAL."
	fi
	echo "$(date -u ) - scheduled $new/$updated packages$old."
	rm $NEW $UPDATED > /dev/null
	echo "$(date -u) - Done updating Arch Linux repositories, currently $TOTAL packages scheduled."
}

update_archlinux_repositories

# vim: set sw=0 noet :
