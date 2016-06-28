#!/usr/bin/perl -w
#
#                            PUBLIC DOMAIN NOTICE
#                National Center for Biotechnology Information
#
#  This software/database is a "United States Government Work" under the
#  terms of the United States Copyright Act.  It was written as part of
#  the author's official duties as a United States Government employee and
#  thus cannot be copyrighted.  This software/database is freely available
#  to the public for use. The National Library of Medicine and the U.S.
#  Government have not placed any restriction on its use or reproduction.
#
#  Although all reasonable efforts have been taken to ensure the accuracy
#  and reliability of the software and data, the NLM and the U.S.
#  Government do not and cannot warrant the performance or results that
#  may be obtained by using this software or data. The NLM and the U.S.
#  Government disclaim all warranties, express or implied, including
#  warranties of performance, merchantability or fitness for any particular
#  purpose.
#

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

my ($ConfFile, $TargetWorkingCopy) = @ARGV;

my $Conf = NCBI::SVN::Replay::Conf->new($ConfFile);

my $Class = $InitPath ? 'NCBI::SVN::Replay::Init' : 'NCBI::SVN::Replay';

exit $Class->new(MyName => $ScriptName)->Run($Conf,
    $TargetWorkingCopy, $InitPath)

# vim: filetype=perl tabstop=4 shiftwidth=4 softtabstop=4 expandtab
