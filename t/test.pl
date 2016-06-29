#!/usr/bin/perl -w
#
# This is a poor man's replacement for the 'prove' program that
# comes standard with Perl 5.8.3.

use strict;
use warnings;

use Test::Harness;

use File::Basename;
use File::Find ();

my @Tests;

File::Find::find(
    {
        wanted => sub {push @Tests, $_ if m/\.t$/so},
        no_chdir => 1
    }, dirname($0));

runtests @Tests

# vim: filetype=perl tabstop=4 shiftwidth=4 softtabstop=4 expandtab
