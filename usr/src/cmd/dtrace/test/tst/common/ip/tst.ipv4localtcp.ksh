#!/usr/bin/ksh
#
# CDDL HEADER START
#
# The contents of this file are subject to the terms of the
# Common Development and Distribution License (the "License").
# You may not use this file except in compliance with the License.
#
# You can obtain a copy of the license at usr/src/OPENSOLARIS.LICENSE
# or http://www.opensolaris.org/os/licensing.
# See the License for the specific language governing permissions
# and limitations under the License.
#
# When distributing Covered Code, include this CDDL HEADER in each
# file and include the License file at usr/src/OPENSOLARIS.LICENSE.
# If applicable, add the following below this CDDL HEADER, with the
# fields enclosed by brackets "[]" replaced with your own identifying
# information: Portions Copyright [yyyy] [name of copyright owner]
#
# CDDL HEADER END
#

#
# Copyright (c) 2008, 2010, Oracle and/or its affiliates. All rights reserved.
#

#
# Test {ip,tcp}:::{send,receive} of IPv4 TCP to local host.
#
# This may fail due to:
#
# 1. A change to the ip stack breaking expected probe behavior,
#    which is the reason we are testing.
# 2. The lo0 interface missing or not up.
# 3. The local ssh service is not online.
# 4. An unlikely race causes the unlocked global send/receive
#    variables to be corrupted.
#
# This test performs a TCP connection and checks that at least the
# following packet counts were traced:
#
# 3 x ip:::send (2 during the TCP handshake, then a FIN)
# 3 x tcp:::send (2 during the TCP handshake, then a FIN)
# 2 x ip:::receive (1 during the TCP handshake, then the FIN ACK)
# 2 x tcp:::receive (1 during the TCP handshake, then the FIN ACK)

# The actual count tested is 5 each way, since we are tracing both
# source and destination events.
#
# For this test to work, we are assuming that the TCP handshake and
# TCP close will enter the IP code path and not use tcp fusion.
#

if (( $# != 1 )); then
	print -u2 "expected one argument: <dtrace-path>"
	exit 2
fi

dtrace=$1
local=127.0.0.1
tcpport=22
DIR=/var/tmp/dtest.$$

mkdir $DIR
cd $DIR

cat > test.pl <<-EOPERL
	use IO::Socket;
	my \$s = IO::Socket::INET->new(
	    Proto => "tcp",
	    PeerAddr => "$local",
	    PeerPort => $tcpport,
	    Timeout => 3);
	die "Could not connect to host $local port $tcpport" unless \$s;
	close \$s;
	#
	# Sleep for one second to assure that our D script has ample time to
	# see all events induced by the close
	#
	sleep 1;
EOPERL

$dtrace -c 'perl test.pl' -qs /dev/stdin <<EODTRACE
BEGIN
{
	ipsend = tcpsend = ipreceive = tcpreceive = 0;
}

ip:::send
/args[2]->ip_saddr == "$local" && args[2]->ip_daddr == "$local" &&
    args[4]->ipv4_protocol == IPPROTO_TCP/
{
	ipsend++;
}

tcp:::send
/args[2]->ip_saddr == "$local" && args[2]->ip_daddr == "$local"/
{
	tcpsend++;
}

ip:::receive
/args[2]->ip_saddr == "$local" && args[2]->ip_daddr == "$local" &&
    args[4]->ipv4_protocol == IPPROTO_TCP/
{
	ipreceive++;
}

tcp:::receive
/args[2]->ip_saddr == "$local" && args[2]->ip_daddr == "$local"/
{
	tcpreceive++;
}

END
{
	printf("Minimum TCP events seen\n\n");
	printf("ip:::send - %s\n", ipsend >= 5 ? "yes" : "no");
	printf("ip:::receive - %s\n", ipreceive >= 5 ? "yes" : "no");
	printf("tcp:::send - %s\n", tcpsend >= 5 ? "yes" : "no");
	printf("tcp:::receive - %s\n", tcpreceive >= 5 ? "yes" : "no");
}
EODTRACE

status=$?

cd /
/usr/bin/rm -rf $DIR

exit $status
