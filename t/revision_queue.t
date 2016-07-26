#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More tests => 2;

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
use NCBI::SVN::Replay::RevisionQueue;

use File::Temp qw(tempdir);

my $SVNBase = NCBI::SVN::Base->new(MyName => basename($0));

my $TmpDir = tempdir(CLEANUP => 1);

my $NumberOfTestRepos = 3;

my @TestRepos;

for (my $i = 0; $i < $NumberOfTestRepos; ++$i)
{
    push @TestRepos, TestRepo->new(ParentDir => $TmpDir, %$SVNBase)
}

my $FileName = 'number';

my @SourceRepoConf;

my $RepoIndex = 0;

for my $TestRepo (@TestRepos)
{
    push @SourceRepoConf,
        {
            RepoName => 'test_repo_' . $RepoIndex,
            RootURL => $TestRepo->{RepoURL},
            PathMapping =>
            [
                {
                    SourcePath => $FileName,
                    TargetPath => $FileName . '_' . $RepoIndex
                }
            ]
        }
}

my $NextNumber = 0;

sub CreateRevisionAndSetTime
{
    my ($TestRepo, $Time) = @_;

    $TestRepo->Put($FileName, $NextNumber++ . "\n");

    my $RevisionNumber = $TestRepo->Commit("Update '$FileName'");

    $SVNBase->{SVN}->RunSubversion(qw(propset --revprop svn:date -r),
        $RevisionNumber, $Time, $TestRepo->{RepoURL});
}

my $Year = 2020;

my @CommitOrder = (1, 0, 1, 0, 2, 2, 0, 1, 1, 2);

for my $RepoIndex (@CommitOrder)
{
    my $Time = $Year++ . '-07-26T03:05:40.000000Z';

    CreateRevisionAndSetTime($TestRepos[$RepoIndex], $Time)
}

my @SourceRepos;

for my $SourceRepoConf (@SourceRepoConf)
{
    push @SourceRepos, NCBI::SVN::Replay::SourceRepo->new(
        Conf => $SourceRepoConf, TargetPathInfo => {},
        %$SVNBase)
}

my $RevisionQueue = NCBI::SVN::Replay::RevisionQueue->new(
    SourceRepos => \@SourceRepos, %$SVNBase);

ok(ref($RevisionQueue) eq 'NCBI::SVN::Replay::RevisionQueue');

my @ExpectedOrder = map {$SourceRepoConf[$_]->{RepoName}} @CommitOrder;

my @ActualOrder;

while (my $Revision = $RevisionQueue->NextOldestRevision())
{
    push @ActualOrder, $Revision->{SourceRepo}->{Conf}->{RepoName}
}

is_deeply(\@ExpectedOrder, \@ActualOrder, 'Revisions go in expected order');

# vim: filetype=perl tabstop=4 shiftwidth=4 softtabstop=4 expandtab
