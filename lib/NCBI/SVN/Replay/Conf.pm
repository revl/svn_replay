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

sub BuildTree
{
    my ($Paths, $ConfFile, $PathType) = @_;

    my $Root = {};

    for my $Path (@$Paths)
    {
        ref($Root) eq 'HASH' or die "$ConfFile\: " .
            "$PathType path cannot be empty.";

        my $NodeRef = \$Root;

        my @Dirs = split('/', $Path);

        @Dirs > 0 or die "$ConfFile\: invalid $PathType path '$Path'.\n";

        for my $Dir (@Dirs)
        {
            next unless $Dir;

            ref($$NodeRef) eq 'HASH' or die "$ConfFile\: " .
                "$PathType paths '$Path' and '$$NodeRef' overlap.\n";

            $NodeRef = \(${$NodeRef}->{$Dir} ||= {})
        }

        if (ref($$NodeRef) ne 'HASH')
        {
            die "$ConfFile\: " . ($Path eq $$NodeRef ?
                "found duplicate $PathType paths '$Path'.\n" :
                "$PathType paths '$Path' and '$$NodeRef' overlap.\n")
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
    my ($Conf, $ParamName, $ConfFile) = @_;

    my $Value = $Conf->{$ParamName};
    if (!defined $Value)
    {
        die "$ConfFile\: missing required parameter '$ParamName'.\n"
    }
    if (ref($Value) eq 'ARRAY' && @$Value == 0)
    {
        die "$ConfFile\: '$ParamName' cannot be empty.\n"
    }

    return $Value
}

sub Load
{
    my ($Class, $ConfFile) = @_;

    my $Conf = do $ConfFile;

    unless (ref($Conf) eq 'HASH')
    {
        die "$ConfFile\: $@\n" if $@;
        die "$ConfFile\: $!\n" unless defined $Conf;
        die "$ConfFile\: configuration file must return a hash\n"
    }

    $Conf->{ConfFile} = $ConfFile;

    return new($Class, $Conf)
}

sub new
{
    my ($Class, $Conf) = @_;

    my $ConfFile = $Conf->{ConfFile};

    unless ($ConfFile)
    {
        my @Caller = caller(0);

        use File::Basename;

        $ConfFile = basename($Caller[1]) . ':' . $Caller[2]
    }

    my $SourceRepositories = RequireParam($Conf,
        'SourceRepositories', $ConfFile);

    my @TargetPaths;

    for my $SourceRepoConf (@$SourceRepositories)
    {
        my $RepoName = RequireParam($SourceRepoConf, 'RepoName', $ConfFile);

        if ($RepoName !~ m/^[:A-Z_a-z][-.0-9:A-Z_a-z]*$/gso)
        {
            die "$ConfFile\: invalid repository name '$RepoName'\n"
        }

        RequireParam($SourceRepoConf, 'RootURL', $ConfFile);

        my @SourcePaths;
        my @RepoTargetPaths;

        my $PathMapping = RequireParam($SourceRepoConf,
            'PathMapping', $ConfFile);

        my $SourcePathToMapping = $SourceRepoConf->{SourcePathToMapping} = {};

        for my $Mapping (@$PathMapping)
        {
            my $SourcePath = RequireParam($Mapping, 'SourcePath', $ConfFile);
            push @SourcePaths, $SourcePath;

            $SourcePathToMapping->{$SourcePath} = $Mapping;

            my $TargetPath = RequireParam($Mapping, 'TargetPath', $ConfFile);
            push @TargetPaths, $TargetPath;
            push @RepoTargetPaths, $TargetPath;

            $Mapping->{ExclusionTree} =
                BuildTree($Mapping->{ExclusionList} || [],
                    $ConfFile, 'exclusion')
        }

        $SourceRepoConf->{SourcePathTree} =
            BuildTree(\@SourcePaths, $ConfFile, 'source');

        $SourceRepoConf->{TargetPaths} = \@RepoTargetPaths
    }

    # Build a tree of target paths just to make sure they don't overlap.
    BuildTree(\@TargetPaths, $ConfFile, 'target');

    $Conf->{TargetPaths} = \@TargetPaths;

    return bless $Conf, $Class
}

1

# vim: filetype=perl tabstop=4 shiftwidth=4 softtabstop=4 expandtab
