#!/usr/bin/env perl

use 5.010;
use strict;
use Test::More;
use FindBin;
use lib "t/lib","lib","$FindBin::Bin/../blib/lib","$FindBin::Bin/../blib/arch";
use EV;
use Scalar::Util 'weaken';
use Guard;

use_ok 'EV::Scribe';

my $isok = 0;
{
	my $g = guard {
		ok $isok, "guard ok";
	};
	my $c = EV::Scribe->new({
		host => '0.0.0.0',
		port => 1234,
		connected => sub {
			$g;
		},
	});
	ok $c;
	weaken(my $xc = $c);
	$isok = 1;
	undef $c;
	ok !$xc;
}
$isok = 0;

done_testing();
