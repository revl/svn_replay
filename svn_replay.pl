#!/usr/bin/perl -w

use strict;

my ($ScriptDir, $ScriptName);

use File::Spec;

BEGIN
{
    my $Volume;
    my $NewScriptDir;

    my $ScriptPathname = $0;

    ($Volume, $ScriptDir, $ScriptName) = File::Spec->splitpath($ScriptPathname);

    $ScriptDir = File::Spec->rel2abs(File::Spec->catpath($Volume,
        $ScriptDir, ''));

    while ($ScriptPathname = eval {readlink $ScriptPathname})
    {
        ($Volume, $NewScriptDir) = File::Spec->splitpath($ScriptPathname);

        $ScriptDir = File::Spec->rel2abs(File::Spec->catpath($Volume,
            $NewScriptDir, ''), $ScriptDir);
    }
}

use lib $ScriptDir;

use NCBI::SVN::Replay;

use Getopt::Long qw(:config permute no_getopt_compat no_ignore_case);

sub Help
{
    print <<EOF;
Usage: $ScriptName <config_file>
NCBI Subversion repository mirroring and restructuring tool.

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
my ($Help);

GetOptions('help|h|?' => \$Help) or UsageError();

# Configuration file name is the first non-option argument.
my $ConfFile = shift @ARGV;

unless (defined $ConfFile)
{
    $Help ? Help() : UsageError()
}

my $Configuration;

unless (ref($Configuration = do $ConfFile) eq 'HASH')
{
    die "$ScriptName\: $@\n" if $@;
    die "$ScriptName\: $ConfFile\: $!\n" unless defined $Configuration;
    die "$ScriptName\: configuration file '$ConfFile' must return a hash\n"
}

exit NCBI::SVN::Replay->new(MyName => $ScriptName)->Run($Configuration)
