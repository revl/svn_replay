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
use NCBI::SVN::Replay::Conf;
use NCBI::SVN::Replay::Init;
use NCBI::SVN::Replay;

use File::Temp qw(tempdir);
use Cwd;

my $OrigCurrDir = getcwd();

my $TmpDir = tempdir(CLEANUP => 1);

my $TestRepo = TestRepo->new(ParentDir => $TmpDir);

my $Conf = NCBI::SVN::Replay::Conf->new(
    {
        SourceRepositories =>
        [
            {
                RepoName => 'test_repo',
                RootURL => $TestRepo->{RepoURL},
                PathMapping =>
                [
                    {
                        SourcePath => 'trunk/outer/inner',
                        TargetPath => 'trunk/inner'
                    },
                    {
                        SourcePath => 'branches/feat/outer/inner',
                        TargetPath => 'branches/feat/inner'
                    }
                ]
            }
        ]
    });

my $TargetRepoPath = File::Temp::tempnam($TmpDir, 'target_repo_XXXXXX');
my $TargetWorkingCopy = File::Temp::tempnam($TmpDir, 'target_wd_XXXXXX');

my $Init = NCBI::SVN::Replay::Init->new(
    MyName => basename($0), SVN => $TestRepo->{SVN});

$Init->Run($Conf, $TargetWorkingCopy, $TargetRepoPath);

$TestRepo->Put('trunk/outer/inner/file_1.txt', "file_1\n");
$TestRepo->Commit('Initial commit');

my $Replay = NCBI::SVN::Replay->new(%$Init);

ok(ref($Replay) eq 'NCBI::SVN::Replay');

$Replay->Run($Conf, $TargetWorkingCopy);

ok(-f "$TargetWorkingCopy/trunk/inner/file_1.txt");

ok(!-e "$TargetWorkingCopy/branches");

$TestRepo->Copy('trunk', 'branches/feat');
$TestRepo->Commit('Create branch "feat"');

$Replay->Run($Conf, $TargetWorkingCopy);

ok(-f "$TargetWorkingCopy/branches/feat/inner/file_1.txt");

$TestRepo->Delete('branches/feat');
$TestRepo->Commit('Delete branch "feat"');

$Replay->Run($Conf, $TargetWorkingCopy);

ok(-d "$TargetWorkingCopy/branches/feat");
ok(!-e "$TargetWorkingCopy/branches/feat/inner");

$TestRepo->Put('trunk/new_outer/inner/file_2.txt', "file_2\n");
$TestRepo->Commit('Create a new version of "outer"');
$TestRepo->Move('trunk/new_outer', 'trunk/outer');
$TestRepo->Commit('New version of "inner", indirectly');

$Replay->Run($Conf, $TargetWorkingCopy);

ok(-f "$TargetWorkingCopy/trunk/inner/file_2.txt");
ok(!-e "$TargetWorkingCopy/trunk/inner/file_1.txt");

chdir $OrigCurrDir;

# vim: filetype=perl tabstop=4 shiftwidth=4 softtabstop=4 expandtab
