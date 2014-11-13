use 5.008008;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'EV::Scribe',
    VERSION_FROM      => 'lib/EV/Scribe.pm', # finds $VERSION
    PREREQ_PM         => {}, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/EV/Scribe.pm', # retrieve abstract from module
       AUTHOR         => 'Vladimir Perepelitsa <v.perepelitsa@localdomain>') : ()),
    LIBS              => [''], # e.g., '-lm'
    DEFINE            => '', # e.g., '-DHAVE_SOMETHING'
    INC               => '-I.', # e.g., '-I. -I/usr/include/other'
	# Un-comment this if you add C files to link with later:
    # OBJECT            => '$(O_FILES)', # link all the C files too
);

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
	LIBS              => ['-lcares19'],
	DEFINE            => '-g -ggdb -O0',
	CONFIGURE => sub {
		require EV::MakeMaker;
		return {EV::MakeMaker::ev_args(
			INC               => '-I/usr/include/c-ares19 -I. -I./evcnn/src -I./xsmy',
		)};
	},
);
