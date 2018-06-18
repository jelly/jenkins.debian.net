#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# Copyright © 2014 Holger Levsen <holger@layer-acht.org>
#           © 2015-2018 Mattia Rizzolo <mattia@mapreri.org>
# Licensed under GPL-2
#
# Depends: python3
#
# Get the output of dd-list(1) and turn it into some nice html

import os
import re
import lzma
import html as HTML
from urllib.request import urlopen
from subprocess import Popen, PIPE
from tempfile import NamedTemporaryFile

from rblib import query_db
from rblib.confparse import log
from rblib.const import DISTRO_BASE, DISTRO_URI, DISTRO_URL, SUITES
from rblib.models import Package
from rblib.html import create_main_navigation, write_html_page


arch = 'amd64' # the arch is only relevant for link targets here
mirror = 'http://deb.debian.org/debian'

for suite in SUITES:
    remotefile = mirror + '/dists/' + suite + '/main/source/Sources.xz'
    os.makedirs('/tmp/reproducible', exist_ok=True)
    with NamedTemporaryFile(dir='/tmp/reproducible') as sources:
        log.info('Downloading sources file for ' + suite + ': ' + remotefile)
        xfile = lzma.decompress(urlopen(remotefile).read())
        if xfile:
            sources.write(xfile)
        else:
            log.error('Failed to get the ' + suite + 'sources')
            continue
        query = "SELECT s.name " + \
                "FROM results AS r JOIN sources AS s ON r.package_id=s.id " + \
                "WHERE r.status='FTBR' AND s.suite='{suite}'"
        try:
            pkgs = [x[0] for x in query_db(query.format(suite=suite))]
        except IndexError:
            log.error('Looks like there are no unreproducible packages...')
        p = Popen(('dd-list --stdin --sources ' + sources.name).split(),
                  stdout=PIPE, stdin=PIPE, stderr=PIPE)
        out, err = p.communicate(input=('\n'.join(pkgs)).encode())
        if err:
            log.error('dd-list printed some errors:\n' + err.decode())
        log.debug('dd-list output:\n' + out.decode())

        html = '<p>The following maintainers and uploaders are listed '
        html += 'for packages in ' + suite + ' which have built '
        html += 'unreproducibly. Please note that the while the link '
        html += 'always points to the amd64 version, it\'s possible that'
        html += 'the unreproducibility is only present in another architecture(s).</p>\n<p><pre>'
        out = out.decode().splitlines()
        get_mail = re.compile('<(.*)>')
        for line in out:
            if line[0:3] == '   ':
                line = line.strip().split(None, 1)
                html += '    '
                # the final strip() is to avoid a newline
                html += Package(line[0]).html_link(suite, arch).strip()
                try:
                    html += ' ' + line[1]  # eventual uploaders sign
                except IndexError:
                    pass
            elif line.strip():  # be sure this is not just an empty line
                email = get_mail.findall(line.strip())[0]
                html += HTML.escape(line.strip())
                html += '<a name="{maint}" href="#{maint}">&para;</a>'.format(
                    maint=email)
            html += '\n'
        html += '</pre></p>'
        title = 'Maintainers of unreproducible packages in ' + suite
        destfile = DISTRO_BASE + '/' + suite + '/index_dd-list.html'
        suite_arch_nav_template = DISTRO_URI + '/{{suite}}/index_dd-list.html'
        left_nav_html = create_main_navigation(suite=suite, arch=arch,
            displayed_page='dd_list', no_arch=True,
            suite_arch_nav_template=suite_arch_nav_template)
        write_html_page(title, html, destfile, style_note=True,
                        left_nav_html=left_nav_html)
        log.info('%s/%s/index_dd-list.html published', DISTRO_URL, suite)
