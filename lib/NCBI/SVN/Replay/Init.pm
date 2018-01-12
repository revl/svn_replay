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

package NCBI::SVN::Replay::Init;

use strict;
use warnings;

use base qw(NCBI::SVN::Base);

use NCBI::SVN::Replay::Conf;

sub Run
{
    my ($Self, $Conf, $TargetWorkingCopy, $InitPath) = @_;

    if (-d $InitPath)
    {
        die "$Self->{MyName}: cannot create repository: " .
            "$InitPath already exists.\n"
    }

    if (-d $TargetWorkingCopy)
    {
        die "$Self->{MyName}: error: the workinig copy " .
            "directory '$TargetWorkingCopy' already exists.\n"
    }

    my $SVN = $Self->{SVN};

    my $EarliestRevisionTime;

    print "Picking the earliest revision date...\n";

    for my $SourceRepoConf (@{$Conf->{SourceRepositories}})
    {
        my $InitialRevisionTime = $SVN->ReadRevProps(0,
            $SourceRepoConf->{RootURL})->{'svn:date'};

        unless ($EarliestRevisionTime)
        {
            $EarliestRevisionTime = $InitialRevisionTime
        }
        elsif ($EarliestRevisionTime gt $InitialRevisionTime)
        {
            $EarliestRevisionTime = $InitialRevisionTime
        }
    }

    die unless $EarliestRevisionTime;

    print "Creating a new repository...\n";

    $SVN->RunOrDie(qw(svnadmin create), $InitPath);

    print "Installing a dummy pre-revprop-change hook script...\n";

    my $HookScript = "$InitPath/hooks/pre-revprop-change";

    open my $Hook, '>', $HookScript or die "$HookScript: $!\n";
    print $Hook "#!/bin/sh\n\nexit 0\n";
    close $Hook;
    chmod 0755, $HookScript or die "$HookScript: $!\n";

    require File::Spec;

    my $URL = 'file://' . File::Spec->rel2abs($InitPath);

    print "Setting svn:date...\n";

    $SVN->RunSubversion(qw(propset --revprop -r0 svn:date),
        $EarliestRevisionTime, $URL);

    print "Checking out revision 0...\n";

    $SVN->RunSubversion('checkout', $URL, $TargetWorkingCopy);

    print "The repository has been created. You may want\n" .
        "to disable representation sharing by setting\n" .
        "enable-rep-sharing = false\n" .
        "in $InitPath/db/fsfs.conf.\n";

    return 0
}

1

# vim: filetype=perl tabstop=4 shiftwidth=4 softtabstop=4 expandtab
