#!/usr/bin/env perl

BEGIN {
	push @INC, qw(../blib/lib ../blib/arch);
}
use Time::HiRes 'time','sleep';

use EV;
use EV::Scribe;
use Data::Dumper;
$Data::Dumper::Useqq = 1;

my $s;$s = EV::Scribe->new({
	host => 'grepmaillog10.corp.mail.ru',
	port => 1463,
	connected => sub {
		my $c = shift;
		warn "connected";
		my $start = time;
		$c->log([
				(
					{category => 'f-win87-test', message => "b".("x"x( 1024*1024*2 ))."e"},
				)
		], sub {
			warn sprintf "delivered in %0.2fs: @_", time - $start;
			$c->disconnect;
		});
	},
	disconnected => sub {
		my $c = shift;
		warn "disconnected";
	},
});
$s->connect;

EV::loop;
undef $s;
