# $Id: 33-NSEC3-hash.t 1389 2015-09-09 13:09:43Z willem $	-*-perl-*-
#

use strict;
use Test::More;
use Net::DNS;

my @prerequisite = qw(
		Digest::SHA
		Net::DNS::RR::NSEC3;
		);

foreach my $package (@prerequisite) {
	next if eval "require $package";
	plan skip_all => "$package not installed";
	exit;
}

plan tests => 12;


my $algorithm = 1;
my $iteration = 12;
my $salt      = pack 'H*', 'aabbccdd';


ok( Net::DNS::RR::NSEC3::name2hash( 1, 'example' ), "defaulted arguments" );
ok( Net::DNS::RR::NSEC3::name2hash( 1, 'example', 12, $salt ), "explicit arguments" );


my %testcase = (			## test vectors from RFC5155
	'example'	=> '0p9mhaveqvm6t7vbl5lop2u3t2rp3tom',
	'a.example'	=> '35mthgpgcu1qg68fab165klnsnk3dpvl',
	'ai.example'	=> 'gjeqe526plbf1g8mklp59enfd789njgi',
	'ns1.example'	=> '2t7b4g4vsa5smi47k61mv5bv1a22bojr',
	'ns2.example'	=> 'q04jkcevqvmu85r014c7dkba38o0ji5r',
	'w.example'	=> 'k8udemvp1j2f7eg6jebps17vp3n8i58h',
	'*.w.example'	=> 'r53bq7cc2uvmubfu5ocmm6pers9tk9en',
	'x.w.example'	=> 'b4um86eghhds6nea196smvmlo4ors995',
	'y.w.example'	=> 'ji6neoaepv8b5o6k4ev33abha8ht9fgc',
	'x.y.w.example' => '2vptu5timamqttgl4luu9kg21e0aor3s',
	);


my @name = qw(example a.example ai.example ns1.example ns2.example
		w.example *.w.example x.w.example y.w.example x.y.w.example);

foreach my $name (@name) {
	my $hash = $testcase{$name};
	my @args = ( $algorithm, $name, $iteration, $salt );
	is( Net::DNS::RR::NSEC3::name2hash(@args), $hash, "H($name)" );
}


exit;

