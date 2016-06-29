#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More tests => 3;

use File::Basename;
use File::Spec;

my @LibDirs;

BEGIN
{
    my $TestDir = File::Spec->rel2abs(dirname($0));

    push @LibDirs, File::Spec->catdir($TestDir, 'lib'),
        File::Spec->catdir(dirname($TestDir), 'lib')
}

use lib @LibDirs;

use NCBI::SVN::Replay::Conf;

my $Conf =
{
    SourceRepositories =>
    [
        {
            RepoName => 'test',
            RootURL => 'file:///home/nobody/test_repo',
            PathMapping =>
            [
                {
                    SourcePath => 'from',
                    TargetPath => 'to'
                }
            ],
            DiscardSvnExternals => 1
        }
    ]
};

$Conf = NCBI::SVN::Replay::Conf->new($Conf); my $Line = __LINE__;

# Verify that the caller is used when configuration is not
# loaded from a file.
is($Conf->{ConfFile}, basename($0) . ':' . $Line, '$Conf->{ConfFile}');

# Make sure the correct class is instantiated...
isa_ok($Conf, 'NCBI::SVN::Replay::Conf', '$Conf');

# ...and the object is also a hash.
isa_ok($Conf, 'HASH', '$Conf');


# vim: filetype=perl tabstop=4 shiftwidth=4 softtabstop=4 expandtab
