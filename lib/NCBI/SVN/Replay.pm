package NCBI::SVN::Replay;

use strict;
use warnings;

use base qw(NCBI::SVN::Base);

use NCBI::SVN::Replay::Conf;

use File::Find ();

my $CommitCredentials;
my $OriginalRevPropName = 'ncbi:original-revision';

my $LineContinuation = '  ... ';

# Global variables
my ($SVN, $TargetRepositoryURL);

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
    my ($CopyFromTargetURL, $CopyFromTargetRev, $TargetPathname) = @_;

    print $LineContinuation .
        "cp $CopyFromTargetURL\@$CopyFromTargetRev $TargetPathname\n";

    $SVN->RunSubversion('cp',
        $CopyFromTargetURL . '@' . $CopyFromTargetRev, $TargetPathname);
}

sub Export
{
    my ($SourceURL, $RevisionNumber, $TargetPathname) = @_;

    print $LineContinuation .
        "export --force $SourceURL\@$RevisionNumber $TargetPathname\n";

    $SVN->RunSubversion(qw(export --force),
        $SourceURL . '@' . $RevisionNumber, $TargetPathname)
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

my $LogChunkSize = 100;

sub FindTargetRevBySourceRev
{
    my ($SourceRevNumber) = @_;

    my $TargetRevisions = $SVN->ReadLog('--limit',
        $LogChunkSize, $TargetRepositoryURL);

    for (;;)
    {
        my $TargetRevNumber = 0;

        for my $TargetRev (@$TargetRevisions)
        {
            $TargetRevNumber = $TargetRev->{Number};

            my $OriginalRev = $SVN->ReadSubversionStream(qw(pg --revprop -r),
                $TargetRevNumber, $OriginalRevPropName, $TargetRepositoryURL);

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
            die "Could not find revision by original revision $SourceRevNumber.\n"
                if $TargetRevNumber <= 0;

            my $Bound = $TargetRevNumber > $LogChunkSize ?
                $TargetRevNumber - $LogChunkSize + 1 : 1;

            $TargetRevisions = $SVN->ReadLog('-r',
                $TargetRevNumber . ':' . $Bound, $TargetRepositoryURL);

            last if @$TargetRevisions;

            $TargetRevNumber = $Bound - 1
        }
    }
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
        $CopyFromTargetURL, $CopyFromTargetRev) = @_;

    Copy($CopyFromTargetURL, $CopyFromTargetRev, $TargetPathname);

    Export($SourceURL, $RevisionNumber, $TargetPathname);

    if (-f $TargetPathname)
    {
        ResetProps($SourceURL, $RevisionNumber, $TargetPathname)
    }
    else
    {
        my @PathnamesToResetPropsFor;

        File::Find::find(
            {
                wanted => sub
                {
                    if (m/\/\.svn$/so)
                    {
                        $File::Find::prune = 1;

                        return
                    }

                    push @PathnamesToResetPropsFor, [JoinPaths($SourceURL,
                        CutOffParent($File::Find::name, $TargetPathname)),
                            $File::Find::name]
                },
                no_chdir => 1
            }, $TargetPathname);

        for (@PathnamesToResetPropsFor)
        {
            my ($URL, $Pathname) = @$_;

            ResetProps($URL, $RevisionNumber, $Pathname)
        }
    }
}

sub AddPathByCopyImitation
{
    my ($TargetPathname, $SourceURL, $RevisionNumber, $Mapping) = @_;

    print "[add-by-copy-imitation]\n";

    Export($SourceURL, $RevisionNumber, $TargetPathname);

    if (IsFile($RevisionNumber, $SourceURL))
    {
        Add($TargetPathname);

        ResetProps($SourceURL, $RevisionNumber, $TargetPathname)
    }
    else
    {
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

            ResetProps(JoinPaths($SourceURL, $RelativePath),
                $RevisionNumber, $Pathname)
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
        $CopyFromTargetURL, $CopyFromTargetRev) = @_;

    print "R         $TargetPath [in-place]\n";

    my $Tree = {'/' => 1};

    for my $Path ($SVN->ReadSubversionLines(qw(ls -R -r), $CopyFromTargetRev,
        $CopyFromTargetURL . '@' . $CopyFromTargetRev))
    {
        my $Node = $Tree;

        $Node = ($Node->{$_} ||= {}) for split('/', $Path)
    }

    my (@PathnamesToResetPropsFor, @PathnamesToRemove, @RelativePathnamesToAdd);

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

                    push @PathnamesToResetPropsFor, [JoinPaths($SourceURL,
                        $RelativePath), $File::Find::name]
                }
                else
                {
                    push @PathnamesToRemove, $File::Find::name
                }
            },
            no_chdir => 1
        }, $TargetPath);

    for (@PathnamesToResetPropsFor)
    {
        my ($URL, $Pathname) = @$_;

        ResetProps($URL, $RevisionNumber, $Pathname)
    }

    for my $Pathname (@PathnamesToRemove)
    {
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
        $CopyFromTargetURL, $CopyFromTargetRev) = @_;

    print "[replace-by-copying]\n";

    if (IsFile($RevisionNumber, $SourceURL))
    {
        Delete($TargetPathname);

        Copy($CopyFromTargetURL, $CopyFromTargetRev, $TargetPathname);

        Export($SourceURL, $RevisionNumber, $TargetPathname);

        ResetProps($SourceURL, $RevisionNumber, $TargetPathname)
    }
    else
    {
        for my $RelativePath (ReplaceDirectory($TargetPathname, $SourceURL,
            $RevisionNumber, $CopyFromTargetURL, $CopyFromTargetRev))
        {
            AddPathByCopying($TargetPathname . $RelativePath,
                $SourceURL . $RelativePath, $RevisionNumber,
                    $CopyFromTargetURL . $RelativePath, $CopyFromTargetRev)
        }
    }
}

sub ReplacePathByCopyImitation
{
    my ($TargetPathname, $SourceURL, $RevisionNumber, $Mapping) = @_;

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
        for my $RelativePath (ReplaceDirectory($TargetPathname, $SourceURL,
            $RevisionNumber, $SourceURL, $RevisionNumber))
        {
            AddPathByCopyImitation($TargetPathname . $RelativePath,
                $SourceURL . $RelativePath, $RevisionNumber, $Mapping)
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

    my $SourceRepoConf = $Revision->{SourceRepoConf};

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
    my ($Self, $Revision) = @_;

    my ($SourceRepoConf, $RevisionNumber) =
        @$Revision{qw(SourceRepoConf Number)};

    my ($RootURL, $SourcePathTree, $SourcePathToMapping) =
        @$SourceRepoConf{qw(RootURL SourcePathTree SourcePathToMapping)};

    $Revision->{HasChangedWorkingCopy} = 0;

    for (@{$Revision->{ChangedPaths}})
    {
        my ($Change, $ChangedSourcePath, $CopyFromSourcePath, $CopyFromSourceRev) = @$_;

        if ($Change !~ m/^[AMDR]$/so)
        {
            die "Unknown type of change '$Change' in " .
                "revision $RevisionNumber of $RootURL\n"
        }

        $ChangedSourcePath =~ s/^\/+//so;

        my @DescendantSourcePaths;

        my $SourcePathAncestor = $SourcePathTree->TracePath(
            $ChangedSourcePath, \@DescendantSourcePaths);

        # The changed path must be either a descendant or an ancestor
        # of a source path. Otherwise, it will be skipped.
        if (defined $SourcePathAncestor)
        {
            my $Mapping = $SourcePathToMapping->{$SourcePathAncestor};

            my $RelativePath =
                CutOffParent($ChangedSourcePath, $SourcePathAncestor);

            next if defined $Mapping->{ExclusionTree}->TracePath($RelativePath);

            BeginWorkingCopyChange($Revision);

            my $TargetPathname =
                JoinPaths($Mapping->{TargetPath}, $RelativePath);

            CreateMissingParentDirs($TargetPathname);

            my $SourceURL = JoinPaths($RootURL, $ChangedSourcePath);

            if ($Change eq 'D')
            {
                Delete($TargetPathname)
            }
            elsif ($Change eq 'M')
            {
                if (IsFile($RevisionNumber, $SourceURL))
                {
                    print "M         $TargetPathname\n";

                    Export($SourceURL, $RevisionNumber, $TargetPathname)
                }

                ResetProps($SourceURL, $RevisionNumber, $TargetPathname)
            }
            else # $Change is either 'A' or 'R'.
            {
                # Methods AddPath() and ReplacePath()
                my $Action = $Change eq 'A' ? 'AddPath' : 'ReplacePath';
                my @Args = ($TargetPathname, $SourceURL, $RevisionNumber);

                if ($CopyFromSourcePath)
                {
                    $CopyFromSourcePath =~ s/^\/+//so;

                    my ($CopyFromSourcePathAncestor,
                        $CopyMapping, $CopyRelativePath);

                    if (defined($CopyFromSourcePathAncestor =
                        $SourcePathTree->TracePath($CopyFromSourcePath)) and
                        $CopyMapping = $SourcePathToMapping->{
                            $CopyFromSourcePathAncestor} and
                        !defined($CopyMapping->{ExclusionTree}->TracePath(
                            $CopyRelativePath =
                                CutOffParent($CopyFromSourcePath,
                                    $CopyFromSourcePathAncestor))))
                    {
                        # Methods AddPathByCopying() and ReplacePathByCopying()
                        $Action .= 'ByCopying';
                        push @Args, JoinPaths($TargetRepositoryURL,
                                JoinPaths($CopyMapping->{TargetPath}, $CopyRelativePath)),
                            FindTargetRevBySourceRev($CopyFromSourceRev)
                    }
                    else
                    {
                        # Methods AddPathByCopyImitation() and
                        # ReplacePathByCopyImitation()
                        $Action .= 'ByCopyImitation';
                        push @Args, $Mapping
                    }
                }

                $Self->can($Action)->(@Args)
            }
        }
        elsif (@DescendantSourcePaths)
        {
            if ($Change eq 'M')
            {
                # Ignore localized ancestor modifications.
                next
            }
            elsif ($Change eq 'D')
            {
                BeginWorkingCopyChange($Revision);

                for my $SourcePath (map {$_->[1]} @DescendantSourcePaths)
                {
                    my $TargetPathname =
                        $SourcePathToMapping->{$SourcePath}->{TargetPath};

                    Delete($TargetPathname) if -e $TargetPathname
                }
            }
            else # $Change is either 'A' or 'R'.
            {
                # Ignore modifications that are not copies.
                next unless $CopyFromSourcePath;

                BeginWorkingCopyChange($Revision);

                $CopyFromSourcePath =~ s/^\/+//so;

                my $CopyFromTargetRev =
                    FindTargetRevBySourceRev($CopyFromSourceRev);

                for (@DescendantSourcePaths)
                {
                    my ($RelativePath, $SourcePath) = @$_;

                    my $Mapping = $SourcePathToMapping->{$SourcePath};

                    my $TargetPathname = $Mapping->{TargetPath};

                    my $SourceURL = JoinPaths($RootURL, $SourcePath);

                    eval
                    {
                        $SVN->ReadInfo("$SourceURL\@$RevisionNumber")
                    };
                    if ($@)
                    {
                        Delete($TargetPathname) if -e $TargetPathname
                    }
                    else
                    {
                        my $Action;
                        my @Args = ($TargetPathname, $SourceURL, $RevisionNumber);

                        unless (-e $TargetPathname)
                        {
                            CreateMissingParentDirs($TargetPathname);

                            $Action = 'AddPath'
                        }
                        else
                        {
                            $Action = 'ReplacePath'
                        }

                        my $LocalCopyFromSourcePath =
                            JoinPaths($CopyFromSourcePath, $RelativePath);

                        my ($CopyFromSourcePathAncestor,
                            $CopyMapping, $CopyRelativePath) = @_;

                        if (defined($CopyFromSourcePathAncestor =
                            $SourcePathTree->TracePath($LocalCopyFromSourcePath)) and
                            $CopyMapping = $SourcePathToMapping->{
                                $CopyFromSourcePathAncestor} and
                            !defined $CopyMapping->{ExclusionTree}->TracePath(
                            $CopyRelativePath = CutOffParent(
                                $LocalCopyFromSourcePath,
                                    $CopyFromSourcePathAncestor)))
                        {
                            # Methods AddPathByCopying() and ReplacePathByCopying()
                            $Action .= 'ByCopying';
                            push @Args, JoinPaths($TargetRepositoryURL,
                                JoinPaths($TargetPathname, $CopyRelativePath)),
                                $CopyFromTargetRev
                        }
                        else
                        {
                            # Methods AddPathByCopyImitation() and
                            # ReplacePathByCopyImitation()
                            $Action .= 'ByCopyImitation';
                            push @Args, $Mapping
                        }

                        $Self->can($Action)->(@Args)
                    }
                }
            }
        }
    }

    if ($Revision->{HasChangedWorkingCopy})
    {
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

            my $RevProps = $SVN->ReadRevProps($RevisionNumber, $RootURL);

            delete $RevProps->{'svn:log'};
            delete $RevProps->{'svn:author'} unless $CommitCredentials;

            $RevProps->{$OriginalRevPropName} = $RevisionNumber;

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

sub IsNewer
{
    my ($Heap, $Index1, $Index2) = @_;

    return $Heap->[$Index1]->[0]->{Time} gt $Heap->[$Index2]->[0]->{Time}
}

sub PushRevisionArray
{
    my ($Heap, $RevisionArray) = @_;

    push @$Heap, $RevisionArray;

    my $Parent;
    my $Child = $#$Heap;

    while ($Child > 0 && IsNewer($Heap, $Parent = $Child >> 1, $Child))
    {
        @$Heap[$Parent, $Child] = @$Heap[$Child, $Parent];
        $Child = $Parent
    }
}

sub PopRevisionArray
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

sub Run
{
    my ($Self, $ConfFile, $TargetWorkingCopy) = @_;

    my $Conf = NCBI::SVN::Replay::Conf->new($ConfFile);

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

    $SVN->RunSubversion(qw(update --ignore-externals));

    my $TargetPathInfo = $SVN->ReadInfo('.', grep {-d} @{$Conf->{TargetPaths}});

    $TargetRepositoryURL = $TargetPathInfo->{'.'}->{Root};

    my @RevisionArrayHeap;

    for my $SourceRepoConf (@{$Conf->{SourceRepositories}})
    {
        my $LastOriginalRev = 0;

        for my $TargetPath (@{$SourceRepoConf->{TargetPaths}})
        {
            if (my $Info = $TargetPathInfo->{$TargetPath})
            {
                my $OriginalRev = $SVN->ReadSubversionStream(
                    qw(pg --revprop -r), $Info->{LastChangedRev},
                        $OriginalRevPropName, $TargetPath);

                chomp $OriginalRev;

                if ($OriginalRev eq '')
                {
                    die "Property '$OriginalRevPropName' is not " .
                        "set for revision $Info->{LastChangedRev}.\n"
                }

                $LastOriginalRev = $OriginalRev
                    if $LastOriginalRev < $OriginalRev
            }
        }

        print "Reading what's new in '$SourceRepoConf->{RepoName}' " .
            "since revision $LastOriginalRev...\n";

        my $Head = $SourceRepoConf->{StopAtRevision} || 'HEAD';

        my $Revisions = $SVN->ReadLog("-r$Head:$LastOriginalRev",
            $SourceRepoConf->{RootURL});

        if ($LastOriginalRev != 0)
        {
            pop(@$Revisions)->{Number} == $LastOriginalRev or die 'Logic error'
        }

        print $LineContinuation . scalar(@$Revisions) . " new revisions.\n";

        if (@$Revisions)
        {
            for my $Revision (@$Revisions)
            {
                $Revision->{SourceRepoConf} = $SourceRepoConf
            }

            PushRevisionArray(\@RevisionArrayHeap, [reverse @$Revisions])
        }
    }

    return 0 unless @RevisionArrayHeap;

    print "Applying new revision changes...\n";

    my $ChangesApplied = 0;

    while (my $Revisions = PopRevisionArray(\@RevisionArrayHeap))
    {
        $ChangesApplied += $Self->ApplyRevisionChanges(shift @$Revisions);

        PushRevisionArray(\@RevisionArrayHeap, $Revisions) if @$Revisions
    }

    print $LineContinuation . ($ChangesApplied ?
        "$ChangesApplied change(s) applied.\n" : "no relevant changes.\n");

    return 0
}

1
