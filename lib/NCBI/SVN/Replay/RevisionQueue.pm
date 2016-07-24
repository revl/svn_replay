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

package NCBI::SVN::Replay::RevisionQueue;

use base qw(NCBI::SVN::Base);

sub IsNewer
{
    my ($Heap, $Index1, $Index2) = @_;

    return $Heap->[$Index1]->[0]->{Time} gt $Heap->[$Index2]->[0]->{Time}
}

sub InsertRevision
{
    my ($Heap, $SourceRepo) = @_;

    if (my $Revision = $SourceRepo->NextRevision())
    {
        $Revision->{SourceRepo} = $SourceRepo;

        push @$Heap, $Revision;

        my $Parent;
        my $Child = $#$Heap;

        while ($Child > 0 && IsNewer($Heap, $Parent = $Child >> 1, $Child))
        {
            @$Heap[$Parent, $Child] = @$Heap[$Child, $Parent];
            $Child = $Parent
        }
    }
}

sub ExtractOldestRevision
{
    my ($Heap) = @_;

    if (@$Heap > 1)
    {
        my $Child = 0;
        my $Parent = $#$Heap;
        my $NewSize = $Parent - 1;

        do
        {
            @$Heap[$Parent, $Child] = @$Heap[$Child, $Parent];

            $Parent = $Child;
            $Child <<= 1;

            return pop @$Heap if $Child > $NewSize;

            ++$Child if $Child < $NewSize && IsNewer($Heap, $Child, $Child + 1)
        }
        while (IsNewer($Heap, $Parent, $Child))
    }

    return pop @$Heap
}

sub new
{
    my $Class = shift;

    my $Self = $Class->SUPER::new(@_);

    my $SourceRepos = $Self->{SourceRepos};

    die if not defined $SourceRepos;

    my $Heap = $Self->{Heap} = [];

    for my $SourceRepo (@$SourceRepos)
    {
        InsertRevision($Heap, $SourceRepo)
    }

    return $Self
}

sub NextOldestRevision
{
    my ($Self) = @_;

    my $Heap = $Self->{Heap};

    my $Revision = ExtractOldestRevision($Heap);

    InsertRevision($Heap, $Revision->{SourceRepo}) if $Revision;

    return $Revision
}

1

# vim: filetype=perl tabstop=4 shiftwidth=4 softtabstop=4 expandtab
