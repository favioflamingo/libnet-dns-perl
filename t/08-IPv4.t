# $Id: 08-IPv4.t 1484 2016-05-27 15:01:52Z willem $ -*-perl-*-

use strict;
use Test::More;
use t::NonFatal;

use Net::DNS;

my $debug = 0;

my @hints = qw(
		198.41.0.4
		192.228.79.201
		192.33.4.12
		199.7.91.13
		192.203.230.10
		192.5.5.241
		192.112.36.4
		198.97.190.53
		192.36.148.17
		192.58.128.30
		193.0.14.129
		199.7.83.42
		202.12.27.33
		);


exit( plan skip_all => 'Online tests disabled.' ) if -e 't/online.disabled';
exit( plan skip_all => 'Online tests disabled.' ) unless -e 't/online.enabled';


eval {
	my $resolver = new Net::DNS::Resolver( igntc => 1 );
	exit plan skip_all => 'No nameservers' unless $resolver->nameservers;

	my $reply = $resolver->send(qw(. NS IN)) || die;

	my @ns = grep $_->type eq 'NS', $reply->answer, $reply->authority;
	exit plan skip_all => 'Local nameserver broken' unless scalar @ns;

	1;
} || exit( plan skip_all => 'Non-responding local nameserver' );


eval {
	my $resolver = new Net::DNS::Resolver( nameservers => [@hints] );
	exit plan skip_all => 'No IPv4 transport' unless $resolver->nameservers;

	my $reply = $resolver->send(qw(. NS IN)) || die;
	my $from = $reply->answerfrom();

	my @ns = grep $_->type eq 'NS', $reply->answer, $reply->authority;
	exit plan skip_all => "Unexpected response from $from" unless scalar @ns;

	exit plan skip_all => "Non-authoritative response from $from" unless $reply->header->aa;

	1;
} || exit( plan skip_all => 'Unable to reach global root nameservers' );


my $IP = eval {
	my $resolver = new Net::DNS::Resolver( igntc => 1 );
	my $nsreply = $resolver->send(qw(net-dns.org NS IN)) || die;
	my @nsdname = map $_->nsdname, grep $_->type eq 'NS', $nsreply->answer;

	# assume any IPv4 net-dns.org nameserver will do
	$resolver->force_v4(1);
	$resolver->nameservers(@nsdname);

	my @ip = $resolver->nameservers();
	scalar(@ip) ? [@ip] : undef;
} || exit( plan skip_all => 'Unable to reach target nameserver' );

my $NOIP = '0.0.0.0';

diag join( "\n\t", 'will use nameservers', @$IP ) if $debug;

Net::DNS::Resolver->debug($debug);


plan tests => 82;

NonFatalBegin();


{
	my $resolver = Net::DNS::Resolver->new( nameservers => $IP );

	my $udp = $resolver->send(qw(net-dns.org SOA IN));
	ok( $udp, '$resolver->send(...)	UDP' );

	$resolver->usevc(1);

	my $tcp = $resolver->send(qw(net-dns.org SOA IN));
	ok( $tcp, '$resolver->send(...)	TCP' );
}


{
	my $resolver = Net::DNS::Resolver->new( nameservers => $IP );
	$resolver->dnssec(1);
	$resolver->udppacketsize(513);

	$resolver->igntc(1);
	my $udp = $resolver->send(qw(net-dns.org DNSKEY IN));
	ok( $udp && $udp->header->tc, '$resolver->send(...)	truncated UDP reply' );

	$resolver->igntc(0);
	my $retry = $resolver->send(qw(net-dns.org DNSKEY IN));
	ok( $retry && !$retry->header->tc, '$resolver->send(...)	automatic TCP retry' );
}


{
	my $resolver = Net::DNS::Resolver->new( nameservers => $IP );
	$resolver->igntc(0);

	my $udp = $resolver->bgsend(qw(net-dns.org SOA IN));
	ok( $udp, '$resolver->bgsend(...)	UDP' );
	while ( $resolver->bgbusy($udp) ) { sleep 1; }
	ok( $resolver->bgisready($udp), '$resolver->bgisready($udp)' );
	ok( $resolver->bgread($udp),	'$resolver->bgread($udp)' );

	$resolver->usevc(1);

	my $tcp = $resolver->bgsend(qw(net-dns.org SOA IN));
	ok( $tcp,		     '$resolver->bgsend(...)	TCP' );
	ok( $resolver->bgread($tcp), '$resolver->bgread($tcp)' );

	ok( !$resolver->bgbusy(undef), '!$resolver->bgbusy(undef)' );
	ok( !$resolver->bgread(undef), '!$resolver->bgread(undef)' );

	$resolver->udp_timeout(0);
	ok( !$resolver->bgread( ref($udp)->new ), '!$resolver->bgread(Socket->new)' );
}


{
	my $resolver = Net::DNS::Resolver->new( nameservers => $IP );
	$resolver->dnssec(1);
	$resolver->udppacketsize(513);
	$resolver->igntc(1);

	my $handle = $resolver->bgsend(qw(net-dns.org DNSKEY IN));
	ok( $handle, '$resolver->bgsend(...)	truncated UDP' );
	my $packet = $resolver->bgread($handle);
	ok( $packet && $packet->header->tc, '$resolver->bgread($udp)	ignore UDP truncation' );
}


{
	my $resolver = Net::DNS::Resolver->new( nameservers => $IP );
	$resolver->dnssec(1);
	$resolver->udppacketsize(513);
	$resolver->igntc(0);

	my $handle = $resolver->bgsend(qw(net-dns.org DNSKEY IN));
	ok( $handle, '$resolver->bgsend(...)	truncated UDP' );
	my $packet = $resolver->bgread($handle);
	ok( $packet && !$packet->header->tc, '$resolver->bgread($tcp)	background TCP retry' );
}


{
	my $resolver = Net::DNS::Resolver->new( nameservers => $IP );
	$resolver->dnssec(1);
	$resolver->udppacketsize(513);
	$resolver->igntc(0);

	my $handle = $resolver->bgsend(qw(net-dns.org DNSKEY IN));
	$resolver->nameserver($NOIP);
	my $packet = $resolver->bgread($handle);
	ok( $packet && $packet->header->tc, '$resolver->bgread($udp)	background TCP fail' );
}


{
	my $resolver = Net::DNS::Resolver->new( nameservers => $IP );

	my $handle   = $resolver->bgsend(qw(net-dns.org SOA IN));
	my $appendix = ${*$handle}{net_dns_bg};
	$$appendix[1]->header->id(undef);			# random id
	ok( !$resolver->bgread($handle), '$resolver->bgread($udp)	id mismatch' );
}


{
	my $resolver = Net::DNS::Resolver->new( nameservers => $IP );

	my $handle = $resolver->bgsend(qw(net-dns.org SOA IN));
	delete ${*$handle}{net_dns_bg};
	ok( $resolver->bgread($handle), '$resolver->bgread($udp)	workaround for SpamAssassin' );
}


{
	my $resolver = Net::DNS::Resolver->new( nameservers => $IP );
	$resolver->persistent_udp(1);

	my $handle = $resolver->bgsend(qw(net-dns.org SOA IN));
	ok( $handle,			'$resolver->bgsend(...)	persistent UDP' );
	ok( $resolver->bgread($handle), '$resolver->bgread($udp)' );
	my $test = $resolver->bgsend(qw(net-dns.org SOA IN));
	ok( $test, '$resolver->bgsend(...)	persistent UDP' );
	is( $test, $handle, 'same UDP socket object used' );
}


{
	my $resolver = Net::DNS::Resolver->new( nameservers => $IP );
	$resolver->persistent_tcp(1);
	$resolver->usevc(1);

	my $handle = $resolver->bgsend(qw(net-dns.org SOA IN));
	ok( $handle,			'$resolver->bgsend(...)	persistent TCP' );
	ok( $resolver->bgread($handle), '$resolver->bgread($tcp)' );
	my $test = $resolver->bgsend(qw(net-dns.org SOA IN));
	ok( $test, '$resolver->bgsend(...)	persistent TCP' );
	is( $test, $handle, 'same TCP socket object used' );
	close($handle);
	ok( $resolver->bgsend(qw(net-dns.org SOA IN)), 'connection recovered after close' );
}


{
	my $resolver = Net::DNS::Resolver->new( nameservers => $IP );
	$resolver->srcaddr($NOIP);
	$resolver->srcport(2345);

	my $udp = $resolver->bgsend(qw(net-dns.org SOA IN));
	ok( $udp, '$resolver->bgsend(...)	specify UDP local address & port' );

	$resolver->usevc(1);

	my $tcp = $resolver->bgsend(qw(net-dns.org SOA IN));
	ok( $tcp, '$resolver->bgsend(...)	specify TCP local address & port' );
}


{
	my $resolver = Net::DNS::Resolver->new( nameservers => $IP );
	$resolver->srcport(-1);

	my $udp = $resolver->send(qw(net-dns.org SOA IN));
	ok( !$udp, '$resolver->send(...)	specify bad UDP source port' );

	$resolver->usevc(1);

	my $tcp = $resolver->send(qw(net-dns.org SOA IN));
	ok( !$tcp, '$resolver->send(...)	specify bad TCP source port' );
}


{
	my $resolver = Net::DNS::Resolver->new( nameservers => $IP );
	$resolver->srcport(-1);

	my $udp = $resolver->bgsend(qw(net-dns.org SOA IN));
	ok( !$udp, '$resolver->bgsend(...)	specify bad UDP source port' );

	$resolver->usevc(1);

	my $tcp = $resolver->bgsend(qw(net-dns.org SOA IN));
	ok( !$tcp, '$resolver->bgsend(...)	specify bad TCP source port' );
}


{
	my $resolver = Net::DNS::Resolver->new();
	$resolver->nameservers(qw( ns.net-dns.org ns.nlnetlabs.nl mcvax.nlnet.nl ));
	$resolver->domain('net-dns.org');
	$resolver->igntc(1);

	eval {
		my ($keyrr) = $resolver->query(qw(tsig-md5 KEY))->answer;
		$resolver->tsig($keyrr);
	};

	my $udp = $resolver->send(qw(net-dns.org SOA IN));
	ok( $udp && ( $udp->verifyerr eq 'NOERROR' ), '$resolver->send(...)	UDP + automatic TSIG' );

	$resolver->usevc(1);

	my $tcp = $resolver->send(qw(net-dns.org SOA IN));
	ok( $tcp && ( $tcp->verifyerr eq 'NOERROR' ), '$resolver->send(...)	TCP + automatic TSIG' );

	my $handle = $resolver->bgsend(qw(net-dns.org SOA IN));
	ok( $resolver->bgread($handle), '$resolver->bgsend/read	TCP + automatic TSIG' );
}


{
	my $resolver = Net::DNS::Resolver->new();
	$resolver->nameservers(qw( ns.net-dns.org ns.nlnetlabs.nl mcvax.nlnet.nl ));
	$resolver->igntc(1);

	eval { $resolver->tsig( 'MD5.example', 'MD5keyMD5keyMD5keyMD5keyMD5=' ) };

	my $udp = $resolver->send(qw(net-dns.org SOA IN));
	ok( !$udp, '$resolver->send(...)	UDP + failed TSIG' );

	$resolver->usevc(1);

	my $tcp = $resolver->send(qw(net-dns.org SOA IN));
	ok( !$tcp, '$resolver->send(...)	TCP + failed TSIG' );

	my $handle = $resolver->bgsend(qw(net-dns.org SOA IN));
	ok( !$resolver->bgread($handle), '$resolver->bgsend/read	TCP + failed TSIG' );
}


{
	my $resolver = Net::DNS::Resolver->new();
	$resolver->retrans(0);
	$resolver->retry(0);

	my @query = ( undef, qw(SOA IN) );
	ok( $resolver->query(@query),  '$resolver->query( undef, ... ) defaults to "." ' );
	ok( $resolver->search(@query), '$resolver->search( undef, ... ) defaults to "." ' );

	$resolver->defnames(0);
	$resolver->dnsrch(0);
	ok( $resolver->search(@query), '$resolver->search() without dnsrch & defnames' );
}


{
	my $resolver = Net::DNS::Resolver->new();
	$resolver->searchlist('net');

	my @query = (qw(us SOA IN));
	ok( $resolver->query(@query),  '$resolver->query( name, ... )' );
	ok( $resolver->search(@query), '$resolver->search( name, ... )' );

	$resolver->defnames(0);
	$resolver->dnsrch(0);
	ok( $resolver->query(@query),  '$resolver->query() without defnames' );
	ok( $resolver->search(@query), '$resolver->search() without dnsrch' );
}


{
	my $resolver = Net::DNS::Resolver->new( nameservers => $IP );

	my $udp = $resolver->query(qw(bogus.net-dns.org A IN));
	ok( !$udp, '$resolver->query() nonexistent name	UDP' );

	$resolver->usevc(1);

	my $tcp = $resolver->query(qw(bogus.net-dns.org A IN));
	ok( !$tcp, '$resolver->query() nonexistent name	TCP' );
}


{
	my $resolver = Net::DNS::Resolver->new( nameservers => $IP );
	my $update = new Net::DNS::Update(qw(example.com));
	ok( $resolver->send($update), '$resolver->send() NOTAUTH UDP' );
	$resolver->usevc(1);
	ok( $resolver->send($update), '$resolver->send() NOTAUTH TCP' );
}


{
	my $resolver = Net::DNS::Resolver->new( nameservers => $NOIP );
	$resolver->retrans(0);
	$resolver->retry(0);
	$resolver->tcp_timeout(0);

	my @query = (qw(. SOA IN));
	my $query = new Net::DNS::Packet(@query);
	ok( !$resolver->query(@query),	'$resolver->query() failure' );
	ok( !$resolver->search(@query), '$resolver->search() failure' );

	$query->edns->option( 65001, pack 'x500' );		# pad to force TCP
	ok( !$resolver->send($query),	'$resolver->send() failure' );
	ok( !$resolver->bgsend($query), '$resolver->bgsend() failure' );

	$resolver->usevc(1);
	my $update = new Net::DNS::Update('bogus.example.com');
	ok( !$resolver->send($update), '$resolver->send() update' );
}


{
	my $resolver = Net::DNS::Resolver->new( nameservers => $IP );

	my $mx = 'mx2.t.net-dns.org';
	my @rr = rr( $resolver, $mx, 'MX' );

	is( scalar(@rr), 2, 'Net::DNS::rr() works with specified resolver' );
	is( scalar rr( $resolver, $mx, 'MX' ), 2, 'Net::DNS::rr() works in scalar context' );
	is( scalar rr( $mx, 'MX' ), 2, 'Net::DNS::rr() works with default resolver' );
}


{
	my $resolver = Net::DNS::Resolver->new( nameservers => $IP );

	my $mx = 'mx2.t.net-dns.org';
	my @mx = mx( $resolver, $mx );

	is( scalar(@mx), 2, 'Net::DNS::mx() works with specified resolver' );

	# some people seem to use mx() in scalar context
	is( scalar mx( $resolver, $mx ), 2, 'Net::DNS::mx() works in scalar context' );

	is( scalar mx($mx), 2, 'Net::DNS::mx() works with default resolver' );

	is( scalar mx('bogus.t.net-dns.org'), 0, "Net::DNS::mx() works for bogus name" );
}


{
	my $resolver = Net::DNS::Resolver->new();
	$resolver->nameservers(qw(ns.net-dns.org ns.nlnetlabs.nl mcvax.nlnet.nl));
	$resolver->force_v4(1);
	$resolver->tcp_timeout(10);

	my @zone = $resolver->axfr('net-dns.org');
	ok( scalar(@zone), '$resolver->axfr() returns entire zone in list context' );

	my $iterator = $resolver->axfr('net-dns.org');
	ok( ref($iterator), '$resolver->axfr() returns iterator in scalar context' );

	my $soa = eval { $iterator->() };
	is( ref($soa), 'Net::DNS::RR::SOA', '$iterator->() returns initial SOA RR' );

	my $i;
	eval {
		return unless $soa;
		$soa->serial(undef);				# force SOA mismatch
		while ( $iterator->() ) { $i++; }
	};
	my ($exception) = split /\n/, "$@\n";
	ok( $i, '$iterator->() iterates through remaining RRs' );
	ok( !eval { $iterator->() }, '$iterator->() returns undef after last RR' );
	ok( $exception, "iterator exception\t[$exception]" );

	my $axfr_start = $resolver->axfr_start('net-dns.org');
	ok( $axfr_start, '$resolver->axfr_start()	(historical)' );
	ok( eval { $resolver->axfr_next() }, '$resolver->axfr_next() works' );
	ok( $resolver->answerfrom(), '$resolver->answerfrom() works' );
}


{
	my $resolver = Net::DNS::Resolver->new();
	$resolver->nameservers(qw(ns.net-dns.org));
	$resolver->force_v4(1);
	$resolver->domain('net-dns.org');
	$resolver->tcp_timeout(10);

	eval {
		my ($keyrr) = $resolver->query(qw(tsig-md5 KEY))->answer;
		$resolver->tsig($keyrr);
	};

	my @zone = $resolver->axfr();
	ok( scalar(@zone), '$resolver->axfr() with TSIG verify' );

	my @refusal = $resolver->axfr('bogus.net-dns.org');
	my $refusal = $resolver->errorstring;
	ok( !scalar(@refusal), "refused axfr\t[$refusal]" );

	eval { $resolver->tsig( 'MD5.example', 'MD5keyMD5keyMD5keyMD5keyMD5=' ) };
	my @unverifiable = $resolver->axfr();
	my $errorstring	 = $resolver->errorstring;
	ok( !scalar(@unverifiable), "mismatched key\t[$errorstring]" );

	$resolver->srcport(-1);
	my @badsocket = $resolver->axfr();
	my $badsocket = $resolver->errorstring;
	ok( !scalar(@badsocket), "bad AXFR socket\t[$badsocket]" );

	eval { $resolver->tsig(undef) };
	my ($exception) = split /\n/, "$@\n";
	ok( $exception, "undefined TSIG\t[$exception]" );
}


{
	my $resolver = Net::DNS::Resolver->new( nameservers => $NOIP );
	eval { $resolver->tsig( 'MD5.example', 'MD5keyMD5keyMD5keyMD5keyMD5=' ) };

	my $query = new Net::DNS::Packet(qw(. SOA IN));
	ok( $resolver->bgsend($query), '$resolver->bgsend() + automatic TSIG' );
	ok( $resolver->bgsend($query), '$resolver->bgsend() + existing TSIG' );
}


{
	my $resolver = Net::DNS::Resolver->new();
	$resolver->nameservers();
	ok( !$resolver->send(qw(. NS)), 'no nameservers' );
}


{
	my $resolver = Net::DNS::Resolver->new();
	$resolver->nameserver('cname.t.net-dns.org');
	ok( scalar( $resolver->nameservers ), 'resolve nameserver cname' );
}


{
	my $resolver = Net::DNS::Resolver->new();
	my @warnings;
	local $SIG{__WARN__} = sub { push( @warnings, "@_" ); };
	my $ns = 'bogus.example.com.';
	my @ip = $resolver->nameserver($ns);

	my ($warning) = split /\n/, "@warnings\n";
	ok( $warning, "unresolved nameserver warning\t[$warning]" )
			|| diag "\tnon-existent '$ns' resolved: @ip";
}


NonFatalEnd();

exit;

__END__

