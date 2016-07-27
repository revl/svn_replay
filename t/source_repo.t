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

use TestRepo;
use NCBI::SVN::Replay::SourceRepo;

use File::Temp qw(tempdir);

my $TmpDir = tempdir(CLEANUP => 1);

my $TestRepo = TestRepo->new(ParentDir => $TmpDir);

ok(ref($TestRepo) eq 'TestRepo');

my $FilePath = $TestRepo->Put('a/b/c/hello.txt', "Hello, World!\n");
$TestRepo->Commit('Add hello.txt');

$TestRepo->Put('a/b/c/hello.txt', "Hello, Weird!\n");
$TestRepo->Commit('Update hello.txt');

ok(-e $FilePath);

my $SourceRepoConf =
{
    RepoName => 'test_repo',
    RootURL => $TestRepo->{RepoURL},
    PathMapping =>
    [
        {
            SourcePath => 'a/b/c',
            TargetPath => 'd'
        }
    ]
};

my $SourceRepo = NCBI::SVN::Replay::SourceRepo->new(
    Conf => $SourceRepoConf, TargetPathInfo => {},
    MyName => basename($0), SVN => $TestRepo->{SVN});

ok(ref($SourceRepo) eq 'NCBI::SVN::Replay::SourceRepo');

is($SourceRepo->{MaxBufferSize}, 1000, 'MaxBufferSize default');

is($SourceRepo->OriginalRevPropName(), 'orig-rev:test_repo', 'Orig-repo prop');

# Test SourceRepo::UpdateHeadRev()
is($SourceRepo->UpdateHeadRev(), 0, 'No changes since new()');

$TestRepo->Put('a/b/c/hello.txt', "Hello again!\n");
$TestRepo->Commit('Update hello.txt');

is($SourceRepo->UpdateHeadRev(), 1, 'New HEAD revision');

$SourceRepoConf->{StopAtRevision} = 1;

$SourceRepo = NCBI::SVN::Replay::SourceRepo->new(%$SourceRepo);

$TestRepo->Put('a/b/c/hello.txt', "Hi!\n");
$TestRepo->Commit('Update hello.txt');

is($SourceRepo->UpdateHeadRev(), 0, 'StopAtRevision is unaffected by changes');

# vim: filetype=perl tabstop=4 shiftwidth=4 softtabstop=4 expandtab
