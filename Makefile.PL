use 5.008008;
use ExtUtils::MakeMaker;

=for rpm
BuildRequires: c-ares19-devel
BuildRequires: libev-devel
Requires: c-ares19
Requires: perl-EV
=cut

WriteMakefile(
	NAME              => 'EV::Scribe',
	AUTHOR            => 'Mons Anderson <mons@cpan.org>',
	VERSION_FROM      => 'lib/EV/Scribe.pm',
	ABSTRACT_FROM     => 'lib/EV/Scribe.pm',
	PREREQ_PM         => { EV => 4 },
	LIBS              => ['-lcares110', '-lcares'],
	DEFINE            => '-g -ggdb',
	CONFIGURE => sub {
		require EV::MakeMaker;
		return {EV::MakeMaker::ev_args(
			INC               => '-I/usr/include/c-ares110 -I. -I./evcnn/src -I./xsmy',
		)};
	},
	EXE_FILES => [ 'ex/scribewriter' ],
);
