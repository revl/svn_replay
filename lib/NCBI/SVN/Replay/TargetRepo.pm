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

package NCBI::SVN::Replay::TargetRepo;

use base qw(NCBI::SVN::Base);

sub new
{
    my $Class = shift;

    my $Self = $Class->SUPER::new(@_);

    die if not defined $Self->{TargetPaths};

    my $SVN = $Self->{SVN};

    $SVN->RunSubversion(qw(update --ignore-externals));

    my $TargetPathInfo = $SVN->ReadInfo('.', grep {-e} @{$Self->{TargetPaths}});

    $Self->{TargetPathInfo} = $TargetPathInfo;
    $Self->{RepoURL} = $TargetPathInfo->{'.'}->{Root};

    return $Self
}

my $LogChunkSize = 100;

sub FindTargetRevBySourceRev
{
    my ($Self, $SourceRepo, $SourceRevNumber) = @_;

    my $OriginalRevPropName = $SourceRepo->OriginalRevPropName();

    my $SVN = $Self->{SVN};

    my $RepoURL = $Self->{RepoURL};
    my @TargetPaths = grep {-e} @{$SourceRepo->{Conf}->{TargetPaths}};

    die "Cannot get original revision for $SourceRevNumber\: " .
        "none of the target paths exists yet.\n" unless @TargetPaths;

    my $TargetRevisions = $SVN->ReadLog('--limit', $LogChunkSize,
        $RepoURL, @TargetPaths);

    for (;;)
    {
        my $TargetRevNumber = 0;

        for my $TargetRev (@$TargetRevisions)
        {
            $TargetRevNumber = $TargetRev->{Number};

            my $OriginalRev = $SVN->ReadSubversionStream(qw(pg --revprop -r),
                $TargetRevNumber, $OriginalRevPropName, $RepoURL);

            die "Could not get original revision for $SourceRevNumber\n"
                unless $OriginalRev;

            chomp $OriginalRev;

            if ($OriginalRev <= $SourceRevNumber)
            {
                print "WARNING: using older original revision $OriginalRev\n"
                    if $OriginalRev < $SourceRevNumber;

                return $TargetRevNumber
            }
        }

        --$TargetRevNumber;

        for (;;)
        {
            return 0 if $TargetRevNumber <= 0;

            my $Bound = $TargetRevNumber > $LogChunkSize ?
                $TargetRevNumber - $LogChunkSize + 1 : 1;

            $TargetRevisions = $SVN->ReadLog('-r', "$TargetRevNumber\:$Bound",
                $RepoURL, @TargetPaths);

            last if @$TargetRevisions;

            $TargetRevNumber = $Bound - 1
        }
    }
}

1

# vim: filetype=perl tabstop=4 shiftwidth=4 softtabstop=4 expandtab
