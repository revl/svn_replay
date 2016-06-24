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

package NCBI::SVN::Replay::Conf::DirTree;

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

package NCBI::SVN::Replay::Conf;

my $ConfFile;

sub BuildTree
{
    my ($Paths, $PathType) = @_;

    my $Root = {};

    for my $Path (@$Paths)
    {
        ref($Root) eq 'HASH' or die "$ConfFile\: cannot " .
            "combine an empty path with other $PathType paths.\n";

        my $NodeRef = \$Root;

        for my $Dir (split('/', $Path))
        {
            next unless $Dir;

            ref($$NodeRef) eq 'HASH' or die "$ConfFile\: " .
                "$PathType paths '$Path' and '$$NodeRef' overlap.\n";

            $NodeRef = \(${$NodeRef}->{$Dir} ||= {})
        }

        if (%$$NodeRef)
        {
            die "$ConfFile\: $PathType path '$Path' overlaps other path(s).\n"
        }

        $$NodeRef = $Path
    }

    return bless $Root, 'NCBI::SVN::Replay::Conf::DirTree'
}

sub RequireParam
{
    my ($Hash, $ParamName) = @_;

    my $Value = $Hash->{$ParamName};
    if (!defined $Value || (ref($Value) eq 'ARRAY' && @$Value == 0))
    {
        die "$ConfFile\: missing required parameter '$ParamName'.\n"
    }

    return $Value
}

sub new
{
    my $Class = shift;
    $ConfFile = shift;

    my $Self = do $ConfFile;

    unless (ref($Self) eq 'HASH')
    {
        die "$ConfFile\: $@\n" if $@;
        die "$ConfFile\: $!\n" unless defined $Self;
        die "$ConfFile\: configuration file must return a hash\n"
    }

    my $SourceRepositories = RequireParam($Self, 'SourceRepositories');

    my @TargetPaths;

    for my $SourceRepoConf (@$SourceRepositories)
    {
        RequireParam($SourceRepoConf, 'RepoName');
        RequireParam($SourceRepoConf, 'RootURL');

        my @SourcePaths;
        my @RepoTargetPaths;

        if ($SourceRepoConf->{TargetPath})
        {
            $SourceRepoConf->{PathMapping} = [{SourcePath => '',
                TargetPath => $SourceRepoConf->{TargetPath},
                ExclusionList => $SourceRepoConf->{ExclusionList}}]
        }

        my $PathMapping = RequireParam($SourceRepoConf, 'PathMapping');

        my $SourcePathToMapping = $SourceRepoConf->{SourcePathToMapping} = {};

        for my $Mapping (@$PathMapping)
        {
            my $SourcePath = RequireParam($Mapping, 'SourcePath');
            push @SourcePaths, $SourcePath;

            $SourcePathToMapping->{$SourcePath} = $Mapping;

            my $TargetPath = RequireParam($Mapping, 'TargetPath');
            push @TargetPaths, $TargetPath;
            push @RepoTargetPaths, $TargetPath;

            $Mapping->{ExclusionTree} =
                BuildTree($Mapping->{ExclusionList} || [], 'exclusion')
        }

        $SourceRepoConf->{SourcePathTree} = BuildTree(\@SourcePaths, 'source');

        $SourceRepoConf->{TargetPathTree} =
            BuildTree(\@RepoTargetPaths, 'target');

        $SourceRepoConf->{TargetPaths} = \@RepoTargetPaths
    }

    $Self->{TargetPathTree} = BuildTree(\@TargetPaths, 'target');

    $Self->{TargetPaths} = \@TargetPaths;

    return bless $Self, $Class
}

1

# vim: syntax=perl tabstop=4 shiftwidth=4 softtabstop=4 expandtab
