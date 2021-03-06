# $Id: 34-NSEC3-flags.t 1389 2015-09-09 13:09:43Z willem $	-*-perl-*-
#

use strict;
use Test::More;
use Net::DNS;

my @prerequisite = qw(
		Net::DNS::RR::NSEC3;
		);

foreach my $package (@prerequisite) {
	next if eval "require $package";
	plan skip_all => "$package not installed";
	exit;
}

plan tests => 3;


my $rr = new Net::DNS::RR( type => 'NSEC3' );


my $optout = $rr->optout;
ok( !$optout, 'Boolean optout flag has default value' );

$rr->optout( !$optout );
ok( $rr->optout, 'Boolean optout flag toggled' );

$rr->optout($optout);
ok( !$optout, 'Boolean optout flag restored' );


exit;

__END__


