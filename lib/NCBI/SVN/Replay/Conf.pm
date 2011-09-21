package NCBI::SVN::Replay::Conf;

use strict;
use warnings;

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

    return $Root
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

            if ($Mapping->{ExclusionList})
            {
                $Mapping->{ExclusionTree} =
                    BuildTree($Mapping->{ExclusionList}, 'exclusion')
            }
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
