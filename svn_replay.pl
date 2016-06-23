#!/usr/bin/perl -w

use strict;

my ($LibDir, $ScriptName);

use File::Spec;

BEGIN
{
    my $Volume;

    ($Volume, $LibDir, $ScriptName) = File::Spec->splitpath($0);

    $LibDir = File::Spec->catpath($Volume, $LibDir, '');

    if (my $RealPathname = eval {readlink $0})
    {
        do
        {
            $RealPathname = File::Spec->rel2abs($RealPathname, $LibDir);

            ($Volume, $LibDir, undef) = File::Spec->splitpath($RealPathname);

            $LibDir = File::Spec->catpath($Volume, $LibDir, '')
        }
        while ($RealPathname = eval {readlink $RealPathname})
    }
    else
    {
        $LibDir = File::Spec->rel2abs($LibDir)
    }

    $LibDir = File::Spec->catdir($LibDir, 'lib')
}

use lib $LibDir;

use NCBI::SVN::Replay;
use NCBI::SVN::Replay::Init;

use Getopt::Long qw(:config permute no_getopt_compat no_ignore_case);

sub Help
{
    print <<EOF;
Usage: $ScriptName [-i REPO_PATH] <config_file> <target_working_copy>
NCBI Subversion repository mirroring and restructuring tool.

  -i, --init=REPO_PATH          Create a new target repository
                                and check out revision 0 into
                                a new working copy.

See 'svn_replay.example.conf' for details.
EOF

    exit 0
}

sub UsageError
{
    my ($Error) = @_;

    print STDERR ($Error ? "$ScriptName\: $Error\n" : '') .
        "Type '$ScriptName --help' for usage.\n";

    exit 1
}

# Command line options.
my ($Help, $InitPath);

GetOptions('help|h|?' => \$Help, 'i|init=s' => \$InitPath) or UsageError();

if (@ARGV != 2)
{
    $Help ? Help() : UsageError('invalid number of positional arguments.')
}

my $Class = $InitPath ? 'NCBI::SVN::Replay::Init' : 'NCBI::SVN::Replay';

exit $Class->new(MyName => $ScriptName)->Run(@ARGV, $InitPath)

# vim: syntax=perl tabstop=4 shiftwidth=4 softtabstop=4 expandtab
