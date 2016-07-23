#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More tests => 8;

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

use TestRepoMaker;
use NCBI::SVN::Replay::SourceRepo;

use File::Temp qw(tempdir);

my $TmpDir = tempdir(CLEANUP => 1);

my $TestRepoMaker = TestRepoMaker->new(ParentDir => $TmpDir);

ok(ref($TestRepoMaker) eq 'TestRepoMaker');

my $FilePath = $TestRepoMaker->Put('a/b/c/hello.txt', "Hello, World!\n");
$TestRepoMaker->Commit('Add hello.txt');

$TestRepoMaker->Put('a/b/c/hello.txt', "Hello!\n");
$TestRepoMaker->Commit('Update hello.txt');

ok(-e $FilePath);

my $SourceRepoConf =
{
    RepoName => 'test_repo',
    RootURL => $TestRepoMaker->{RepoURL},
    PathMapping =>
    [
        {
            SourcePath => 'a/b/c',
            TargetPath => 'd'
        }
    ]
};

my $SourceRepo = NCBI::SVN::Replay::SourceRepo->new(Conf => $SourceRepoConf,
    MyName => basename($0), SVN => $TestRepoMaker->{SVN});

ok(ref($SourceRepo) eq 'NCBI::SVN::Replay::SourceRepo');

is($SourceRepo->OriginalRevPropName(), 'orig-rev:test_repo', 'Orig-repo prop');

# Test SourceRepo::UpdateHead()
is($SourceRepo->UpdateHead(), 1, 'First call returns TRUE');

is($SourceRepo->UpdateHead(), 0, 'Second call returns FALSE');

$SourceRepoConf->{StopAtRevision} = 1;

$SourceRepo = NCBI::SVN::Replay::SourceRepo->new(%$SourceRepo);

is($SourceRepo->UpdateHead(), 1, 'First call returns TRUE');

is($SourceRepo->UpdateHead(), 0, 'Second call returns FALSE');


# vim: filetype=perl tabstop=4 shiftwidth=4 softtabstop=4 expandtab
