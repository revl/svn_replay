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

use strict;
use warnings;

package NCBI::SVN::Replay::SourceRepo;

use base qw(NCBI::SVN::Base);

sub new
{
    my $Class = shift;

    my $Self = $Class->SUPER::new(@_);

    die if not defined $Self->{Conf} or not defined $Self->{TargetPathInfo};

    $Self->{LastSyncedRev} = $Self->LastSyncedRev();
    $Self->{HeadRev} = $Self->CurrentHeadRev();
    $Self->{RevisionBuffer} = [];
    $Self->{MaxBufferSize} ||= 1000;

    return $Self
}

sub OriginalRevPropName
{
    my ($Self) = @_;

    return 'orig-rev:' . $Self->{Conf}->{RepoName}
}

sub LastSyncedRev
{
    my ($Self) = @_;

    my $LastSyncedRev = 0;

    for my $TargetPath (@{$Self->{Conf}->{TargetPaths}})
    {
        my $Info = $Self->{TargetPathInfo}->{$TargetPath};

        if ($Info && $Info->{LastChangedRev})
        {
            my $OriginalRevPropName = $Self->OriginalRevPropName();

            my $SyncedRev = $Self->{SVN}->ReadSubversionStream(
                qw(pg --revprop -r), $Info->{LastChangedRev},
                    $OriginalRevPropName, $TargetPath);

            chomp $SyncedRev;

            unless ($SyncedRev)
            {
                die "Property '$OriginalRevPropName' is not " .
                    "set for revision $Info->{LastChangedRev}.\n"
            }

            $LastSyncedRev = $SyncedRev if $LastSyncedRev < $SyncedRev
        }
    }

    return $LastSyncedRev
}

sub CurrentHeadRev
{
    my ($Self) = @_;

    my $Conf = $Self->{Conf};

    return $Conf->{StopAtRevision} ||
        [values %{$Self->{SVN}->ReadInfo($Conf->{RootURL})}]->[0]->{Revision}
}

sub UpdateHeadRev
{
    my ($Self) = @_;

    my $NewHeadRev = $Self->CurrentHeadRev();

    return 0 if $Self->{HeadRev} && $Self->{HeadRev} eq $NewHeadRev;

    $Self->{HeadRev} = $NewHeadRev;

    return 1
}

sub NextRevision
{
    my ($Self) = @_;

    my $RevisionBuffer = $Self->{RevisionBuffer};

    if (!@$RevisionBuffer)
    {
        my $LastSyncedRev = $Self->{LastSyncedRev};
        my $HeadRev = $Self->{HeadRev};

        my $NewRevs = $HeadRev - $LastSyncedRev;

        return undef if $NewRevs <= 0;

        my $BufferSize = $Self->{MaxBufferSize};

        $BufferSize = $NewRevs if $BufferSize > $NewRevs;

        my $Conf = $Self->{Conf};

        print "Reading $BufferSize " .
            ($BufferSize == 1 ? 'revision' : 'revisions') .
            " since r$LastSyncedRev from '$Conf->{RepoName}'...\n";

        my $LastRevInBuffer = $LastSyncedRev + $BufferSize;

        $RevisionBuffer = $Self->{SVN}->ReadLog('-r' .
            ($LastSyncedRev + 1) . ':' . $LastRevInBuffer, $Conf->{RootURL});

        $Self->{RevisionBuffer} = $RevisionBuffer;
        $Self->{LastSyncedRev} = $LastRevInBuffer
    }

    return shift @$RevisionBuffer
}

1

# vim: filetype=perl tabstop=4 shiftwidth=4 softtabstop=4 expandtab
