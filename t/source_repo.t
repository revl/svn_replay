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

use TestRepoMaker;

use File::Temp qw(tempdir);

my $TmpDir = tempdir(CLEANUP => 1);

my $TestRepoMaker = TestRepoMaker->new(ParentDir => $TmpDir);

ok(ref($TestRepoMaker) eq 'TestRepoMaker');

my $FilePath = $TestRepoMaker->Put('a/b/c/hello.txt', "Hello, World!\n");
$TestRepoMaker->Commit('Add hello.txt');

$TestRepoMaker->Put('a/b/c/hello.txt', "Hello!\n");
$TestRepoMaker->Commit('Update hello.txt');

ok(-e $FilePath);

# vim: filetype=perl tabstop=4 shiftwidth=4 softtabstop=4 expandtab
