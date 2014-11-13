#!/usr/bin/env perl

BEGIN {
	if (grep $_ eq '-M', @ARGV) {
		*DLEAK = sub () { 1 };
		require Devel::Leak;
	}
	else {
		*DLEAK = sub () { 0 }
	}
	if (grep $_ eq '-O', @ARGV) {
		*ONE = sub { 1 };
	}
	else {
		*ONE = sub { 0 };
	}
	push @INC, qw(../blib/lib ../blib/arch);
}
use Time::HiRes 'time','sleep';

use EV;
use EV::Scribe;
use Data::Dumper;
$Data::Dumper::Useqq = 1;

my $stop;
my $count;
my $sv;
Devel::Leak::NoteSV($sv) if DLEAK;

sub DES::DESTROY { warn "des" }

use Devel::Hexdump 'xd';

my $s;$s = EV::Scribe->new({
	host => 'grepmaillog10.corp.mail.ru',
	port => 1463,
	connected => bless(sub {
		my $c = shift;
		warn "connected";
		#warn Dumper $c->reqs;
		my $t;$t = EV::timer 0,1,sub {
			undef $t;
			my $start = time;
			$c->log([
				(
					{category => 'f-win87-test', message => "f test 1 from ".time()},
					{category => 'f-win87-test', message => "f test 2 from ".time()},
				)x100
			], sub {
				warn sprintf "delivered in %0.2fs: @_", time - $start;
				$c->disconnect;
			});
		};
		
	},'DES'),
	disconnected => sub {
		my $c = shift;
		warn "disconnected";
	},
});
$s->connect;

EV::loop;
undef $s;

Devel::Leak::CheckSV($sv) if DLEAK;
