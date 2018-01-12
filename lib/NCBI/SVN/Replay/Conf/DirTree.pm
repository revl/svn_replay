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

package NCBI::SVN::Replay::Conf::DirTree;

use strict;
use warnings;

sub CollectDescendants
{
    my ($Node, $Descendants, $Path) = @_;

    while (my ($ChildName, $ChildNode) = each %$Node)
    {
        my $ChildPath = $Path ? $Path . '/' . $ChildName : $ChildName;

        if (ref($ChildNode))
        {
            CollectDescendants($ChildNode, $Descendants, $ChildPath)
        }
        else
        {
            push @$Descendants, [$ChildPath, $ChildNode]
        }
    }
}

sub TracePath
{
    my ($Tree, $Path, $Descendants) = @_;

    return $Tree unless ref $Tree;

    my $Node = $Tree;

    for my $Dir (split('/', $Path))
    {
        next unless $Dir;
        return $Node unless ref $Node;
        return undef unless $Node = $Node->{$Dir}
    }

    return $Node unless ref $Node;

    CollectDescendants($Node, $Descendants) if $Descendants;

    return undef
}

1

# vim: filetype=perl tabstop=4 shiftwidth=4 softtabstop=4 expandtab
