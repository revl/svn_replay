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

package NCBI::SVN::Replay;

use strict;
use warnings;

use base qw(NCBI::SVN::Base);

use NCBI::SVN::Replay::Conf;
use NCBI::SVN::Replay::SourceRepo;
use NCBI::SVN::Replay::TargetRepo;
use NCBI::SVN::Replay::RevisionQueue;

use File::Find ();

# Global variables
my ($SVN, $CommitCredentials);

sub IsFile
{
    my ($RevisionNumber, $Path) = @_;

    my ($Info) = values %{$SVN->ReadInfo('-r',
        $RevisionNumber, $Path . '@' . $RevisionNumber)};

    my $NodeKind = $Info->{NodeKind};

    return $NodeKind eq 'file' ? 1 : $NodeKind eq 'directory' ?
        0 : die "Unknown node kind '$NodeKind'\n"
}

sub Copy
{
    my ($CopyFromURLInTargetRepo, $CopyFromRevInTargetRepo,
        $TargetPathname) = @_;

    my $URLAndRev = $CopyFromURLInTargetRepo . '@' . $CopyFromRevInTargetRepo;

    print "  ... cp $URLAndRev $TargetPathname\n";

    $SVN->RunSubversion('cp', $URLAndRev, $TargetPathname);
}

sub Export
{
    my ($SourceURL, $RevisionNumber, $TargetPathname) = @_;

    $SourceURL .= '@' . $RevisionNumber;

    print '  ... export --ignore-externals --force -q ' .
        "$SourceURL $TargetPathname\n";

    $SVN->RunSubversion(qw(export --ignore-externals --force -q),
        $SourceURL, $TargetPathname)
}

sub Add
{
    my ($TargetPathname) = @_;

    $SVN->RunSubversion(qw(add --no-auto-props -N), $TargetPathname)
}

sub Delete
{
    my ($TargetPathname) = @_;

    $SVN->RunSubversion(qw(rm --force), $TargetPathname)
}

sub CutOffParent
{
    my ($Pathname, $Parent) = @_;

    substr($Pathname, 0, length($Parent), '') eq $Parent or die;
    substr($Pathname, 0, 1, '') eq '/' or die if length($Pathname) > 0;

    return $Pathname
}

sub JoinPaths
{
    my ($Path1, $Path2) = @_;

    return $Path1 && $Path2 ? $Path1 . '/' . $Path2 : $Path1 . $Path2
}

my $DiscardSvnExternals;

sub ResetProps
{
    my ($SourceURL, $RevisionNumber, $TargetPathname) = @_;

    my $OldProps = $SVN->ReadPathProps($TargetPathname);

    my $Props = $SVN->ReadPathProps($SourceURL, $RevisionNumber);

    delete $Props->{'svn:mergeinfo'};

    delete $Props->{'svn:externals'} if $DiscardSvnExternals;

    while (my ($Name, $Value) = each %$Props)
    {
        eval
        {
            $SVN->RunSubversion('propset', $Name, $Value, $TargetPathname)
                if !defined($OldProps->{$Name}) || $Value ne $OldProps->{$Name}
        };
        if ($@)
        {
            print 'WARNING: Could not set property ' .
                "'$Name' on '$TargetPathname': $@\n"
        }
    }

    while (my ($Name, $Value) = each %$OldProps)
    {
        $SVN->RunSubversion('propdel', $Name, $TargetPathname)
            if !defined($Props->{$Name})
    }
}

sub AddPath
{
    my ($TargetPathname, $SourceURL, $RevisionNumber) = @_;

    if (IsFile($RevisionNumber, $SourceURL))
    {
        Export($SourceURL, $RevisionNumber, $TargetPathname);

        Add($TargetPathname)
    }
    else
    {
        $SVN->RunSubversion('mkdir', $TargetPathname)
    }

    ResetProps($SourceURL, $RevisionNumber, $TargetPathname)
}

sub AddPathByCopying
{
    my ($TargetPathname, $SourceURL, $RevisionNumber,
        $CopyFromURLInTargetRepo, $CopyFromRevInTargetRepo, $PathnamesToUpdate) = @_;

    Copy($CopyFromURLInTargetRepo, $CopyFromRevInTargetRepo, $TargetPathname);

    if (-f $TargetPathname)
    {
        $PathnamesToUpdate->{$TargetPathname} = $SourceURL
    }
    else
    {
        File::Find::find(
            {
                wanted => sub
                {
                    if (m/\/\.svn$/so)
                    {
                        $File::Find::prune = 1;

                        return
                    }

                    $PathnamesToUpdate->{$File::Find::name} =
                        JoinPaths($SourceURL,
                            CutOffParent($File::Find::name, $TargetPathname))
                },
                no_chdir => 1
            }, $TargetPathname)
    }
}

sub AddPathByCopyImitation
{
    my ($TargetPathname, $SourceURL, $RevisionNumber,
        $CopyFromURLInSourceRepo, $CopyFromRevInSourceRepo,
        $Mapping, $PathnamesToUpdate) = @_;

    print "[add-by-copy-imitation]\n";

    if (IsFile($RevisionNumber, $SourceURL))
    {
        Export($SourceURL, $RevisionNumber, $TargetPathname);

        Add($TargetPathname);

        ResetProps($SourceURL, $RevisionNumber, $TargetPathname)
    }
    else
    {
        Export($CopyFromURLInSourceRepo, $CopyFromRevInSourceRepo, $TargetPathname);

        my $ExclusionTree = $Mapping->{ExclusionTree};

        my (@PathnamesToRemove, @PathnamesToAdd);

        File::Find::find(
            {
                wanted => sub
                {
                    my $RelativePath =
                        CutOffParent($File::Find::name, $TargetPathname);

                    if (defined $ExclusionTree->TracePath($RelativePath))
                    {
                        $File::Find::prune = 1;

                        push @PathnamesToRemove, $File::Find::name
                    }
                    else
                    {
                        push @PathnamesToAdd, [$File::Find::name, $RelativePath]
                    }
                },
                no_chdir => 1
            },
            $TargetPathname);

        for my $Pathname (@PathnamesToRemove)
        {
            print "D         $Pathname (excluded)\n";

            system(qw(rm -rf), $Pathname)
        }

        for (@PathnamesToAdd)
        {
            my ($Pathname, $RelativePath) = @$_;

            Add($Pathname);

            $PathnamesToUpdate->{$Pathname} =
                JoinPaths($SourceURL, $RelativePath)
        }
    }
}

sub CollectPathnamesToAdd
{
    my ($RelativePathnamesToAdd, $Node, $RelativePath) = @_;

    if (delete($Node->{'/'}))
    {
        while (my ($PathComponent, $SubTree) = each %$Node)
        {
            CollectPathnamesToAdd($RelativePathnamesToAdd, $SubTree,
                "$RelativePath/$PathComponent")
        }
    }
    else
    {
        push @$RelativePathnamesToAdd, $RelativePath
    }
}

sub ReplaceDirectory
{
    my ($TargetPath, $SourceURL, $RevisionNumber,
        $CopyFromURL, $CopyFromRev, $PathnamesToUpdate) = @_;

    print "R         $TargetPath [in-place]\n";

    my $Tree = {'/' => 1};

    for my $Path ($SVN->ReadSubversionLines(qw(ls -R -r), $CopyFromRev,
        $CopyFromURL . '@' . $CopyFromRev))
    {
        my $Node = $Tree;

        $Node = ($Node->{$_} ||= {}) for split('/', $Path)
    }

    my (@PathnamesToRemove, @RelativePathnamesToAdd);

    File::Find::find(
        {
            wanted => sub
            {
                if (m/\/\.svn$/so)
                {
                    $File::Find::prune = 1;

                    return
                }

                my $Node = $Tree;
                my $RelativePath = CutOffParent($File::Find::name, $TargetPath);

                if ($RelativePath)
                {
                    my @PathComponents = split('/', $RelativePath);

                    my $LastComponent = pop @PathComponents;

                    $Node = $Node->{$_} for @PathComponents;

                    unless (exists $Node->{$LastComponent})
                    {
                        $File::Find::prune = 1;

                        push @PathnamesToRemove, $File::Find::name;

                        return
                    }

                    $Node = $Node->{$LastComponent}
                }

                if (-d $File::Find::name)
                {
                    $Node->{'/'} = 1;

                    $PathnamesToUpdate->{$File::Find::name} =
                        JoinPaths($SourceURL, $RelativePath)
                }
                else
                {
                    push @PathnamesToRemove, $File::Find::name
                }
            },
            no_chdir => 1
        }, $TargetPath);

    for my $Pathname (@PathnamesToRemove)
    {
        delete $PathnamesToUpdate->{$Pathname};

        Delete($Pathname)
    }

    CollectPathnamesToAdd(\@RelativePathnamesToAdd, $Tree, '');

    return @RelativePathnamesToAdd
}

sub ReplacePath
{
    my ($TargetPathname, $SourceURL, $RevisionNumber) = @_;

    if (IsFile($RevisionNumber, $SourceURL))
    {
        Delete($TargetPathname);

        Export($SourceURL, $RevisionNumber, $TargetPathname);

        Add($TargetPathname);

        ResetProps($SourceURL, $RevisionNumber, $TargetPathname)
    }
    else
    {
        die "ReplacePath for directories is not implemented.\n"
    }
}

sub ReplacePathByCopying
{
    my ($TargetPathname, $SourceURL, $RevisionNumber,
        $CopyFromURLInTargetRepo, $CopyFromRevInTargetRepo, $PathnamesToUpdate) = @_;

    print "[replace-by-copying]\n";

    if (IsFile($RevisionNumber, $SourceURL))
    {
        Delete($TargetPathname);

        Copy($CopyFromURLInTargetRepo, $CopyFromRevInTargetRepo, $TargetPathname);

        $PathnamesToUpdate->{$TargetPathname} = $SourceURL
    }
    else
    {
        for my $RelativePath (ReplaceDirectory($TargetPathname,
            $SourceURL, $RevisionNumber,
            $CopyFromURLInTargetRepo, $CopyFromRevInTargetRepo,
            $PathnamesToUpdate))
        {
            AddPathByCopying($TargetPathname . $RelativePath,
                $SourceURL . $RelativePath, $RevisionNumber,
                $CopyFromURLInTargetRepo . $RelativePath, $CopyFromRevInTargetRepo,
                $PathnamesToUpdate)
        }
    }
}

sub ReplacePathByCopyImitation
{
    my ($TargetPathname, $SourceURL, $RevisionNumber,
        $CopyFromURLInSourceRepo, $CopyFromRevInSourceRepo,
        $Mapping, $PathnamesToUpdate) = @_;

    print "[replace-by-copy-imitation]\n";

    if (IsFile($RevisionNumber, $SourceURL))
    {
        Delete($TargetPathname);

        Export($SourceURL, $RevisionNumber, $TargetPathname);

        Add($TargetPathname);

        ResetProps($SourceURL, $RevisionNumber, $TargetPathname)
    }
    else
    {
        for my $RelativePath (ReplaceDirectory($TargetPathname,
            $SourceURL, $RevisionNumber,
            $CopyFromURLInSourceRepo, $CopyFromRevInSourceRepo,
            $PathnamesToUpdate))
        {
            AddPathByCopyImitation($TargetPathname . $RelativePath,
                $SourceURL . $RelativePath, $RevisionNumber,
                $CopyFromURLInSourceRepo . $RelativePath, $CopyFromRevInSourceRepo,
                $Mapping, $PathnamesToUpdate)
        }
    }
}

sub CreateMissingParentDirs
{
    my ($TargetPathname) = @_;

    my ($ParentDir) = $TargetPathname =~ m/(.*)\//so;

    if ($ParentDir && !-d $ParentDir)
    {
        print "Creating missing parent directory $ParentDir...\n";

        $SVN->RunSubversion(qw(mkdir --parents), $ParentDir)
    }
}

sub BeginWorkingCopyChange
{
    my ($Revision) = @_;

    my $SourceRepoConf = $Revision->{SourceRepo}->{Conf};

    unless ($Revision->{HasChangedWorkingCopy})
    {
        $Revision->{HasChangedWorkingCopy} = 1;

        print '-' x 80 . "\nApplying revision $Revision->{Number} of '" .
            $SourceRepoConf->{RepoName} . "'...\n";

        $SVN->RunSubversion(qw(update --ignore-externals));

        # Check for uncommitted changes...
        my @LocalChanges = grep(!m/^X/o, $SVN->ReadSubversionLines(
            qw(status --ignore-externals)));

        if (@LocalChanges)
        {
            local $" = "\n  ";
            die "Error: uncommitted changes detected:\n  @LocalChanges\n"
        }

        $DiscardSvnExternals = $SourceRepoConf->{DiscardSvnExternals}
    }
}

sub ApplyRevisionChanges
{
    my ($Self, $Revision, $TargetRepo) = @_;

    my ($SourceRepo, $SourceRevisionNumber) = @$Revision{qw(SourceRepo Number)};

    my $TargetRepositoryURL = $TargetRepo->{RepoURL};

    my $SourceRepoConf = $SourceRepo->{Conf};

    my ($RootURL, $SourcePathTree, $SourcePathToMapping) =
        @$SourceRepoConf{qw(RootURL SourcePathTree SourcePathToMapping)};

    $Revision->{HasChangedWorkingCopy} = 0;

    my %PathnamesToUpdate;

    for (@{$Revision->{ChangedPaths}})
    {
        my ($Change, $ChangedPathInSourceRepo,
            $CopyFromPathInSourceRepo, $CopyFromRevInSourceRepo) = @$_;

        if ($Change !~ m/^[AMDR]$/so)
        {
            die "Unknown type of change '$Change' in " .
                "revision $SourceRevisionNumber of $RootURL\n"
        }

        # Remove the leading slash.
        $ChangedPathInSourceRepo =~ s/^\/+//so;

        my @SourcePaths_ChildrenOfChangedPath;

        my $SourcePath_ParentOfChangedPath = $SourcePathTree->TracePath(
            $ChangedPathInSourceRepo, \@SourcePaths_ChildrenOfChangedPath);

        # In order to be applied, the changed path must be either a descendant
        # or an ancestor of a path configured for replication.
        if (defined $SourcePath_ParentOfChangedPath)
        {
            my $Mapping = $SourcePathToMapping->{$SourcePath_ParentOfChangedPath};

            my $RelativePath = CutOffParent($ChangedPathInSourceRepo,
                $SourcePath_ParentOfChangedPath);

            next if defined $Mapping->{ExclusionTree}->TracePath($RelativePath);

            BeginWorkingCopyChange($Revision);

            my $PathToChangeInTargetRepo =
                JoinPaths($Mapping->{TargetPath}, $RelativePath);

            CreateMissingParentDirs($PathToChangeInTargetRepo);

            my $ChangedPathURL = JoinPaths($RootURL, $ChangedPathInSourceRepo);

            if ($Change eq 'D')
            {
                delete $PathnamesToUpdate{$PathToChangeInTargetRepo};

                Delete($PathToChangeInTargetRepo)
            }
            elsif ($Change eq 'M')
            {
                if (IsFile($SourceRevisionNumber, $ChangedPathURL))
                {
                    print "M         $PathToChangeInTargetRepo\n";

                    Export($ChangedPathURL, $SourceRevisionNumber,
                        $PathToChangeInTargetRepo)
                }

                ResetProps($ChangedPathURL, $SourceRevisionNumber,
                    $PathToChangeInTargetRepo)
            }
            else # $Change is either 'A' or 'R'.
            {
                # Methods AddPath() and ReplacePath()
                my $Action = $Change eq 'A' ? 'AddPath' : 'ReplacePath';
                my @Args = ($PathToChangeInTargetRepo,
                    $ChangedPathURL, $SourceRevisionNumber);

                if ($CopyFromPathInSourceRepo)
                {
                    $CopyFromPathInSourceRepo =~ s/^\/+//so;

                    my ($SourcePath_ParentOfCopyFromPath,
                        $CopyMapping, $RelativeCopyFromPath);

                    if (defined($SourcePath_ParentOfCopyFromPath =
                        $SourcePathTree->TracePath($CopyFromPathInSourceRepo)) and
                        $CopyMapping = $SourcePathToMapping->{
                            $SourcePath_ParentOfCopyFromPath} and
                        !defined($CopyMapping->{ExclusionTree}->TracePath(
                            $RelativeCopyFromPath =
                                CutOffParent($CopyFromPathInSourceRepo,
                                    $SourcePath_ParentOfCopyFromPath))))
                    {
                        # Methods AddPathByCopying() and ReplacePathByCopying()
                        $Action .= 'ByCopying';
                        push @Args, JoinPaths($TargetRepositoryURL,
                                JoinPaths($CopyMapping->{TargetPath}, $RelativeCopyFromPath)),
                            $TargetRepo->FindTargetRevBySourceRev(
                                $SourceRepo, $CopyFromRevInSourceRepo)
                    }
                    else
                    {
                        # Methods AddPathByCopyImitation() and
                        # ReplacePathByCopyImitation()
                        $Action .= 'ByCopyImitation';
                        push @Args, JoinPaths($RootURL, $CopyFromPathInSourceRepo),
                            $CopyFromRevInSourceRepo, $Mapping
                    }

                    push @Args, \%PathnamesToUpdate
                }

                $Self->can($Action)->(@Args)
            }
        }
        elsif (@SourcePaths_ChildrenOfChangedPath)
        {
            if ($Change eq 'M')
            {
                # Ignore localized ancestor modifications.
                next
            }
            elsif ($Change eq 'D')
            {
                BeginWorkingCopyChange($Revision);

                for my $SourcePath (
                    map {$_->[1]} @SourcePaths_ChildrenOfChangedPath)
                {
                    my $TargetPath =
                        $SourcePathToMapping->{$SourcePath}->{TargetPath};

                    if (-e $TargetPath)
                    {
                        delete $PathnamesToUpdate{$TargetPath};

                        Delete($TargetPath)
                    }
                }
            }
            else # $Change is either 'A' or 'R'.
            {
                # Ignore modifications that are not copies.
                next unless $CopyFromPathInSourceRepo;

                BeginWorkingCopyChange($Revision);

                $CopyFromPathInSourceRepo =~ s/^\/+//so;

                my $CopyFromRevInTargetRepo =
                    $TargetRepo->FindTargetRevBySourceRev(
                        $SourceRepo, $CopyFromRevInSourceRepo);

                for (@SourcePaths_ChildrenOfChangedPath)
                {
                    my ($RelativePath, $SourcePath_CopyTarget) = @$_;

                    my $Mapping = $SourcePathToMapping->{$SourcePath_CopyTarget};

                    my $TargetPath = $Mapping->{TargetPath};

                    my $SourcePathURL_CopyTarget = JoinPaths($RootURL, $SourcePath_CopyTarget);

                    eval
                    {
                        $SVN->ReadInfo("$SourcePathURL_CopyTarget\@$SourceRevisionNumber")
                    };
                    if ($@)
                    {
                        if (-e $TargetPath)
                        {
                            delete $PathnamesToUpdate{$TargetPath};

                            Delete($TargetPath)
                        }
                    }
                    else
                    {
                        my $Action;
                        my @Args = ($TargetPath,
                            $SourcePathURL_CopyTarget, $SourceRevisionNumber);

                        unless (-e $TargetPath)
                        {
                            CreateMissingParentDirs($TargetPath);

                            $Action = 'AddPath'
                        }
                        else
                        {
                            $Action = 'ReplacePath'
                        }

                        my $CopyFromSourcePath =
                            JoinPaths($CopyFromPathInSourceRepo, $RelativePath);

                        my ($SourcePath_ParentOfCopyFromPath,
                            $CopyMapping, $RelativeCopyFromPath);

                        if (defined($SourcePath_ParentOfCopyFromPath =
                            $SourcePathTree->TracePath($CopyFromSourcePath)) and
                            $CopyMapping = $SourcePathToMapping->{
                                $SourcePath_ParentOfCopyFromPath} and
                            !defined $CopyMapping->{ExclusionTree}->TracePath(
                            $RelativeCopyFromPath = CutOffParent(
                                $CopyFromSourcePath,
                                    $SourcePath_ParentOfCopyFromPath)))
                        {
                            # Methods AddPathByCopying() and ReplacePathByCopying()
                            $Action .= 'ByCopying';
                            push @Args, JoinPaths($TargetRepositoryURL,
                                JoinPaths($CopyMapping->{TargetPath}, $RelativeCopyFromPath)),
                                $CopyFromRevInTargetRepo
                        }
                        else
                        {
                            # Methods AddPathByCopyImitation() and
                            # ReplacePathByCopyImitation()
                            $Action .= 'ByCopyImitation';
                            push @Args,
                                JoinPaths($RootURL, $CopyFromSourcePath),
                                $CopyFromRevInSourceRepo, $Mapping
                        }

                        push @Args, \%PathnamesToUpdate;

                        $Self->can($Action)->(@Args)
                    }
                }
            }
        }
    }

    for my $Pathname (keys %PathnamesToUpdate)
    {
        if (-e $Pathname)
        {
            my $SourceURL = $PathnamesToUpdate{$Pathname};

            Export($SourceURL, $SourceRevisionNumber, $Pathname) if -f $Pathname;

            ResetProps($SourceURL, $SourceRevisionNumber, $Pathname)
        }
    }

    if ($Revision->{HasChangedWorkingCopy})
    {
        my $PreCommitHook = $SourceRepoConf->{PreCommitHook};

        if ($PreCommitHook && !$PreCommitHook->($Revision))
        {
            print "WARNING: pre-commit hook aborted the commit.\n";
            return 0
        }

        if (grep(m/^\?/o, $SVN->ReadSubversionLines(qw(status --ignore-externals))))
        {
            die "Cannot proceed: not all new files have been added.\n"
        }

        my @AuthParams = $CommitCredentials ? @$CommitCredentials :
            ('--username', $Revision->{Author});

        my $Output = $SVN->ReadSubversionStream(@AuthParams,
            qw(commit --force-log -m), $Revision->{LogMessage});

        my ($NewRevision) = $Output =~ m/Committed revision (\d+)\./o;

        if ($NewRevision)
        {
            print $Output;

            my $RevProps = $SVN->ReadRevProps($SourceRevisionNumber, $RootURL);

            delete $RevProps->{'svn:log'};
            delete $RevProps->{'svn:author'} unless $CommitCredentials;

            $RevProps->{$SourceRepo->OriginalRevPropName()} =
                $SourceRevisionNumber;

            while (my ($Name, $Value) = each %$RevProps)
            {
                $SVN->RunSubversion(@AuthParams,
                    qw(ps --revprop -r), $NewRevision, $Name, $Value)
            }
        }
        else
        {
            print "WARNING: no changes detected.\n";
            return 0
        }
    }

    return $Revision->{HasChangedWorkingCopy}
}

sub Run
{
    my ($Self, $Conf, $TargetWorkingCopy) = @_;

    $SVN = $Self->{SVN};

    if ($CommitCredentials = $Conf->{CommitCredentials})
    {
        $CommitCredentials = ref $CommitCredentials ?
            ['--username', $CommitCredentials->[0],
                '--password', $CommitCredentials->[1]] :
            ['--username', $CommitCredentials]
    }

    chdir $TargetWorkingCopy or
        die "$Self->{MyName}: could not chdir to $TargetWorkingCopy.\n";

    my $TargetRepo = NCBI::SVN::Replay::TargetRepo->new(
            TargetPaths => $Conf->{TargetPaths},
            MyName => $Self->{MyName}, SVN => $SVN);

    my $TargetPathInfo = $TargetRepo->{TargetPathInfo};

    my @SourceRepos;

    for my $SourceRepoConf (@{$Conf->{SourceRepositories}})
    {
        push @SourceRepos, NCBI::SVN::Replay::SourceRepo->new(
            Conf => $SourceRepoConf, TargetPathInfo => $TargetPathInfo,
            MyName => $Self->{MyName}, SVN => $SVN)
    }

    if (@SourceRepos > 1)
    {
        # Iterate over source repositories in a circular way to get
        # HEAD revisions that are consistent with each other.
        my $RepoIndex = 0;
        my $StableHeadCount;

        do
        {
            $SourceRepos[$RepoIndex]->UpdateHeadRev() ?
                $StableHeadCount = 0 : ++$StableHeadCount;

            $RepoIndex = ($RepoIndex + 1) % @SourceRepos
        }
        while ($StableHeadCount != @SourceRepos)
    }

    my $RevisionQueue = NCBI::SVN::Replay::RevisionQueue->new(
        SourceRepos => \@SourceRepos, MyName => $Self->{MyName}, SVN => $SVN);

    my $Revision = $RevisionQueue->NextOldestRevision();

    return 0 unless $Revision;

    print "Applying new revision changes...\n";

    my $ChangesApplied = 0;

    do
    {
        $ChangesApplied += $Self->ApplyRevisionChanges($Revision, $TargetRepo)
    }
    while ($Revision = $RevisionQueue->NextOldestRevision());

    print $ChangesApplied ?  "  ... $ChangesApplied change(s) applied.\n" :
        "  ... no relevant changes.\n";

    return 0
}

1

# vim: filetype=perl tabstop=4 shiftwidth=4 softtabstop=4 expandtab
