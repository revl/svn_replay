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

sub new()
{
    my $Class = shift;

    my $Self = $Class->SUPER::new(@_);

    die if not defined $Self->{Conf};

    return $Self
}

sub OriginalRevPropName()
{
    my ($Self) = @_;

    return 'orig-rev:' . $Self->{Conf}->{RepoName}
}

sub LastOriginalRev()
{
    my ($Self, $TargetPathInfo) = @_;

    my $LastOriginalRev = 0;

    for my $TargetPath (@{$Self->{Conf}->{TargetPaths}})
    {
        if (my $Info = $TargetPathInfo->{$TargetPath})
        {
            my $OriginalRevPropName = $Self->OriginalRevPropName();

            my $OriginalRev = $Self->{SVN}->ReadSubversionStream(
                qw(pg --revprop -r), $Info->{LastChangedRev},
                    $OriginalRevPropName, $TargetPath);

            chomp $OriginalRev;

            unless ($OriginalRev)
            {
                die "Property '$OriginalRevPropName' is not " .
                    "set for revision $Info->{LastChangedRev}.\n"
            }

            $LastOriginalRev = $OriginalRev if $LastOriginalRev < $OriginalRev
        }
    }

    return $LastOriginalRev
}

sub UpdateHead()
{
    my ($Self) = @_;

    my $Conf = $Self->{Conf};

    my $NewHead = $Conf->{StopAtRevision} ||
        [values %{$Self->{SVN}->ReadInfo($Conf->{RootURL})}]->[0]->{Revision};

    return 0 if $Self->{Head} && $Self->{Head} eq $NewHead;

    $Self->{Head} = $NewHead;

    return 1
}

1

# vim: filetype=perl tabstop=4 shiftwidth=4 softtabstop=4 expandtab
