#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More tests => 11;

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

my %ConfHash;

eval {NCBI::SVN::Replay::Conf->new(\%ConfHash)}; my $Line = __LINE__;
my $Caller = basename($0) . ':' . $Line;

# Make sure the caller line number is present in the error message
# when configuration is not loaded from a file.
like($@, qr($Caller), 'Line number in error message');

# Verify that omitting SourceRepositories - the main configuration
# paramer - triggers an error.
like($@, qr(missing.*SourceRepositories), 'Require SourceRepositories');

my @SourceRepositories;

$ConfHash{SourceRepositories} = \@SourceRepositories;

# Verify that at least one source repository is required.
eval {NCBI::SVN::Replay::Conf->new(\%ConfHash)};
like($@, qr(SourceRepositories.*empty), 'At least one repo is required');

my %RepoConf;

push @SourceRepositories, \%RepoConf;

# Verify that RepoName is required.
eval {NCBI::SVN::Replay::Conf->new(\%ConfHash)};
like($@, qr(missing.*RepoName), 'Require RepoName');

$RepoConf{RepoName} = 'test_repo';

# Verify that RootURL is required.
eval {NCBI::SVN::Replay::Conf->new(\%ConfHash)};
like($@, qr(missing.*RootURL), 'Require RootURL');

$RepoConf{RootURL} = 'file:///home/nobody/test_repo';

# Verify that PathMapping is required.
eval {NCBI::SVN::Replay::Conf->new(\%ConfHash)};
like($@, qr(missing.*PathMapping), 'Require PathMapping');

my @PathMapping;

$RepoConf{PathMapping} = \@PathMapping;

# Verify that empty PathMapping array is not allowed.
eval {NCBI::SVN::Replay::Conf->new(\%ConfHash)};
like($@, qr(PathMapping.*empty), 'PathMapping cannot be empty');

my %OneMapping;

push @PathMapping, \%OneMapping;

# Verify that SourcePath is required.
eval {NCBI::SVN::Replay::Conf->new(\%ConfHash)};
like($@, qr(missing.*SourcePath), 'Require SourcePath');

$OneMapping{SourcePath} = 'from/path';

# Verify that TargetPath is required.
eval {NCBI::SVN::Replay::Conf->new(\%ConfHash)};
like($@, qr(missing.*TargetPath), 'Require TargetPath');

$OneMapping{TargetPath} = 'to/path';

# Finally, the next call should succeed.
my $Conf = NCBI::SVN::Replay::Conf->new(\%ConfHash);

# Make sure the correct class is instantiated...
isa_ok($Conf, 'NCBI::SVN::Replay::Conf', '$Conf');

# ...and the object is also a hash.
isa_ok($Conf, 'HASH', '$Conf');


# vim: filetype=perl tabstop=4 shiftwidth=4 softtabstop=4 expandtab
