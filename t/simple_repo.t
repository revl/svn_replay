#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More tests => 1;

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

use SourceRepoMaker;

my $SourceRepoMaker = SourceRepoMaker->new();

ok(ref($SourceRepoMaker) eq 'SourceRepoMaker');

# vim: filetype=perl tabstop=4 shiftwidth=4 softtabstop=4 expandtab
