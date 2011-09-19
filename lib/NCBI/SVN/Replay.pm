package NCBI::SVN::Replay;

use strict;
use warnings;

use base qw(NCBI::SVN::Base);

use File::Find ();

my $CommitCredentials;
my $OriginalRevPropName = 'ncbi:original-revision';

my $LineContinuation = '  ... ';

sub IsFile
{
    my ($SVN, $RevisionNumber, $Path) = @_;

    my ($Info) = values %{$SVN->ReadInfo('-r',
        $RevisionNumber, $Path . '@' . $RevisionNumber)};

    my $NodeKind = $Info->{NodeKind};

    return $NodeKind eq 'file' ? 1 : $NodeKind eq 'directory' ?
        0 : die "Unknown node kind '$NodeKind'\n"
}

sub DownloadFile
{
    my ($SVN, $TargetPathname, $SourceURL, $RevisionNumber) = @_;

    my $Contents = $SVN->ReadFile('-r', $RevisionNumber,
        $SourceURL . '@' . $RevisionNumber);

    open FILE, '>', $TargetPathname or die "$TargetPathname\: $!\n";
    syswrite FILE, $Contents;
    close FILE
}

my $LogChunkSize = 100;

my $TargetRepositoryURL;

sub FindTargetRevBySourceRev
{
    my ($SVN, $SourceRevNumber) = @_;

    my $TargetRevisions = $SVN->ReadLog('--limit', $LogChunkSize, $TargetRepositoryURL);

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

sub TracePath
{
    my ($Tree, $Path, $Descendants) = @_;

    #my ($AncestorChange, $DescendantChange);

    return $Tree unless ref $Tree;

    my $Node = $Tree;

    for my $Dir (split('/', $Path))
    {
        next unless $Dir;
        return $Node unless ref $Node;
        return undef unless $Node = $Node->{$Dir}
    }

    return $Node unless ref $Node;

    if ($Descendants)
    {
        my @Nodes;
        do
        {
            map {ref() ? push @Nodes, $_ : push @$Descendants, $_} values %$Node
        }
        while ($Node = pop @Nodes)
    }

    return undef
}

sub CutOffParent
{
    my ($Pathname, $Parent) = @_;

    substr($Pathname, 0, length($Parent), '') eq $Parent or die;
    substr($Pathname, 0, 1, '') eq '/' or die if length($Pathname) > 0;

    return $Pathname
}

my $DiscardSvnExternals;

sub ResetProps
{
    my ($SVN, $TargetPathname, $SourceURL, $RevisionNumber) = @_;

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
    my ($Self, $SVN, $TargetPathname, $SourceURL, $RevisionNumber) = @_;

    if (IsFile($SVN, $RevisionNumber, $SourceURL))
    {
        DownloadFile($SVN, $TargetPathname, $SourceURL, $RevisionNumber);

        $SVN->RunSubversion(qw(add --no-auto-props), $TargetPathname)
    }
    else
    {
        #eval
        #{
            $SVN->RunSubversion('mkdir', $TargetPathname)
        #};
        #if ($@)
        #{
        #    print "WARNING: Could not mkdir '$TargetPathname': $@\n"
        #}
    }

    ResetProps($SVN, $TargetPathname, $SourceURL, $RevisionNumber)
}

sub AddPathByCopying
{
    my ($Self, $SVN, $TargetPathname,
        $SourceURL, $RevisionNumber, $CopyFromTargetURL, $CopyFromSourceRev) = @_;

    my $CopyFromTargetRev = FindTargetRevBySourceRev($SVN, $CopyFromSourceRev);
    $CopyFromTargetURL .= '@' . $CopyFromTargetRev;

    print $LineContinuation .
        "cp -r $CopyFromTargetRev $CopyFromTargetURL $TargetPathname\n";

    $SVN->RunSubversion(qw(cp -r),
        $CopyFromTargetRev, $CopyFromTargetURL, $TargetPathname)
}

sub AddPathByCopyImitation
{
    my ($Self, $SVN, $TargetPathname,
        $SourceURL, $RevisionNumber, $Mapping) = @_;

    print "AddPathByCopyImitation($TargetPathname, $SourceURL, $RevisionNumber)\n";

    if (IsFile($SVN, $RevisionNumber, $SourceURL))
    {
        DownloadFile($SVN, $TargetPathname, $SourceURL, $RevisionNumber);

        $SVN->RunSubversion(qw(add --no-auto-props), $TargetPathname);

        ResetProps($SVN, $TargetPathname, $SourceURL, $RevisionNumber)
    }
    else
    {
        print "  ... svn export -r$RevisionNumber $SourceURL\@$RevisionNumber $TargetPathname\n";

        $SVN->RunSubversion(qw(export -r), $RevisionNumber,
            $SourceURL . '@' . $RevisionNumber, $TargetPathname);

        my $ExclusionList = $Mapping->{ExclusionList};

        if ($ExclusionList)
        {
            my $TargetPath = $Mapping->{TargetPath};

            $TargetPath = $TargetPath ? "./$TargetPath/" : './';

            system(qw(rm -rf), map {$TargetPath . $_} @$ExclusionList)
        }

        my @PathnamesToAdd;

        File::Find::find(
            {
                wanted => sub {push @PathnamesToAdd, $File::Find::name},
                no_chdir => 1
            },
            $TargetPathname);

        for my $Pathname (@PathnamesToAdd)
        {
            $SVN->RunSubversion(qw(add --no-auto-props -N), $Pathname);

            ResetProps($SVN, $Pathname, $SourceURL . '/' .
                CutOffParent($Pathname, $TargetPathname), $RevisionNumber)
        }
    }
}

sub TraverseReplacementTree
{
    my ($SVN, $Node, $Pathname, $CopyFromTargetURL, $CopyFromTargetRev) = @_;

    if (delete($Node->{'/'}))
    {
        if (-d $Pathname)
        {
            ResetProps($SVN, $Pathname, $CopyFromTargetURL, $CopyFromTargetRev);

            my @PathnamesToAdd;

            while (my ($PathComponent, $SubTree) = each %$Node)
            {
                push @PathnamesToAdd, TraverseReplacementTree($SVN, $SubTree,
                    "$Pathname/$PathComponent",
                        "$CopyFromTargetURL/$PathComponent", $CopyFromTargetRev)
            }

            return @PathnamesToAdd
        }
        else
        {
            $SVN->RunSubversion(qw(rm --force), $Pathname)
        }
    }

    return ([$Pathname, $CopyFromTargetURL])
}

sub ReplaceDirectory
{
    my ($SVN, $TargetPath, $CopyFromTargetURL, $CopyFromTargetRev) = @_;

    my $Tree = {'/' => 1};

    for my $Path ($SVN->ReadSubversionLines(qw(ls -R -r), $CopyFromTargetRev,
        $CopyFromTargetURL . '@' . $CopyFromTargetRev))
    {
        my $Node = $Tree;

        $Node = ($Node->{$_} ||= {}) for split('/', $Path)
    }

    my @PathnamesToRemove;

    File::Find::find(
        {
            wanted => sub
            {
                if (m/\/\.svn$/so)
                {
                    $File::Find::prune = 1
                }
                else
                {
                    my $ExistingPath =
                        CutOffParent($File::Find::name, $TargetPath);
                    my $Node = $Tree;
                    my $Pathname = '';
                    for my $PathComponent (split('/', $ExistingPath))
                    {
                        $Pathname .= '/' if $Pathname;
                        $Pathname .= $PathComponent;
                        if (exists $Node->{$PathComponent})
                        {
                            ($Node = $Node->{$PathComponent})->{'/'} = 1
                        }
                        else
                        {
                            $File::Find::prune = 1;
                            push @PathnamesToRemove, $Pathname
                        }
                    }
                }
            },
            no_chdir => 1
        }, $TargetPath);

    for my $Pathname (@PathnamesToRemove)
    {
        $SVN->RunSubversion(qw(rm --force), $Pathname)
    }

    return TraverseReplacementTree($SVN, $Tree, $TargetPath,
        $CopyFromTargetURL, $CopyFromTargetRev)
}

sub ReplacePath
{
    my ($Self, $SVN, $TargetPathname,
        $SourceURL, $RevisionNumber) = @_;

    if (IsFile($SVN, $RevisionNumber, $SourceURL))
    {
        $SVN->RunSubversion(qw(rm --force), $TargetPathname);

        DownloadFile($SVN, $TargetPathname, $SourceURL, $RevisionNumber);

        $SVN->RunSubversion(qw(add --no-auto-props), $TargetPathname);

        ResetProps($SVN, $TargetPathname, $SourceURL, $RevisionNumber)
    }
    else
    {
        die "ReplacePath for directories is not implemented.\n"
    }
}

sub ReplacePathByCopying
{
    my ($Self, $SVN, $TargetPathname, $SourceURL, $RevisionNumber,
        $CopyFromTargetURL, $CopyFromSourceRev) = @_;

    my $CopyFromTargetRev = FindTargetRevBySourceRev($SVN, $CopyFromSourceRev);

    if (IsFile($SVN, $RevisionNumber, $SourceURL))
    {
        $SVN->RunSubversion(qw(rm --force), $TargetPathname);

        $CopyFromTargetURL .= '@' . $CopyFromTargetRev;

        print $LineContinuation .
            "cp -r $CopyFromTargetRev $CopyFromTargetURL $TargetPathname\n";

        $SVN->RunSubversion(qw(cp -r),
            $CopyFromTargetRev, $CopyFromTargetURL, $TargetPathname)
    }
    else
    {
        for (ReplaceDirectory($SVN, $TargetPathname,
            $CopyFromTargetURL, $CopyFromTargetRev))
        {
            my ($Pathname, $URL) = @$_;

            $URL .= '@' . $CopyFromTargetRev;

            print $LineContinuation .
                "cp -r $CopyFromTargetRev $URL $Pathname\n";

            $SVN->RunSubversion(qw(cp -r), $CopyFromTargetRev, $URL, $Pathname)
        }
    }
}

sub ReplacePathByCopyImitation
{
    my ($Self, $SVN, $TargetPathname,
        $SourceURL, $RevisionNumber, $Mapping) = @_;

    if (IsFile($SVN, $RevisionNumber, $SourceURL))
    {
        $SVN->RunSubversion(qw(rm --force), $TargetPathname);

        DownloadFile($SVN, $TargetPathname, $SourceURL, $RevisionNumber);

        $SVN->RunSubversion(qw(add --no-auto-props), $TargetPathname);

        ResetProps($SVN, $TargetPathname, $SourceURL, $RevisionNumber)
    }
    else
    {
        for (ReplaceDirectory($SVN, $TargetPathname,
            $SourceURL, $RevisionNumber))
        {
            my ($Pathname, $URL) = @$_;

            $Self->AddPathByCopyImitation($SVN, $Pathname,
                $URL, $RevisionNumber, $Mapping)
        }
    }
}

sub ModifyPath
{
    my ($Self, $SVN, $TargetPathname, $SourceURL, $RevisionNumber) = @_;

    if (IsFile($SVN, $RevisionNumber, $SourceURL))
    {
        DownloadFile($SVN, $TargetPathname, $SourceURL, $RevisionNumber)
    }

    ResetProps($SVN, $TargetPathname, $SourceURL, $RevisionNumber)
}

sub DeletePath
{
    my ($Self, $SVN, $TargetPathname) = @_;

    $SVN->RunSubversion('rm', $TargetPathname)
}

sub ApplyRevisionChanges
{
    my ($Self, $SVN, $Revision) = @_;

    my ($SourceRepoConf, $RevisionNumber) =
        @$Revision{qw(SourceRepoConf Number)};

    my ($RootURL, $SourcePathTree, $SourcePathToMapping) =
        @$SourceRepoConf{qw(RootURL SourcePathTree SourcePathToMapping)};
#use Data::Dumper; print Dumper($SourcePathTree);
    my $Changed = 0;

print "--- $Revision->{Number}\n";
    # Sort changes by the change type (Add first, then Delete)
    # sort {$a->[0] cmp $b->[0]}
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
        my $AncestorSourcePath = TracePath($SourcePathTree, $ChangedSourcePath, \@DescendantSourcePaths);

        my $Action;
        my @ActionArgs = ($SVN);

        my @RequireParentsFor;

        if (defined($AncestorSourcePath))
        {
            my $Mapping = $SourcePathToMapping->{$AncestorSourcePath};

            my $RelativePath = CutOffParent($ChangedSourcePath, $AncestorSourcePath);

print " $Change $ChangedSourcePath  : Descendant of '$AncestorSourcePath'\n";
            #next if defined($PathIsExcluded);
if (defined(TracePath($Mapping->{ExclusionTree}, $RelativePath))) {print "PATH $ChangedSourcePath ($RelativePath) IS EXCLUDED\n"; next}

            my $TargetPathname = $Mapping->{TargetPath};
            $TargetPathname .= '/' . $RelativePath if $RelativePath;

            push @ActionArgs, $TargetPathname;

            push @RequireParentsFor, $TargetPathname;

            if ($Change eq 'D')
            {
                $Action = 'DeletePath'
            }
            else
            {
                push @ActionArgs, "$RootURL/$ChangedSourcePath", $RevisionNumber;

                if ($Change eq 'M')
                {
                    $Action = 'ModifyPath'
                }
                else # $Change is either 'A' or 'R'.
                {
                    $Action = $Change eq 'A' ? 'AddPath' : 'ReplacePath';

                    if ($CopyFromSourcePath)
                    {
                        $CopyFromSourcePath =~ s/^\/+//so;

                        my ($CopyFromSourcePathIsDescendantOf,
                            $CopyMapping, $CopyRelativePath);

                        # Check if $CopyFromSourcePath is excluded.
                        if (defined($CopyFromSourcePathIsDescendantOf =
                            TracePath($SourcePathTree, $CopyFromSourcePath)) and
                            $CopyMapping =
                                $SourcePathToMapping->{$CopyFromSourcePathIsDescendantOf} and
                            !defined(TracePath($CopyMapping->{ExclusionTree},
                                $CopyRelativePath =
                                    CutOffParent($CopyFromSourcePath,
                                        $CopyFromSourcePathIsDescendantOf))))
                        {
                            my $CopyFromTargetURL = $TargetRepositoryURL;
                            $CopyFromTargetURL .= '/' . $CopyMapping->{TargetPath}
                                if $CopyMapping->{TargetPath};
                            $CopyFromTargetURL .= '/' . $CopyRelativePath
                                if $CopyRelativePath;

                            $Action .= 'ByCopying';

                            push @ActionArgs, $CopyFromTargetURL, $CopyFromSourceRev
                        }
                        else
                        {
                            $Action .= 'ByCopyImitation';

                            push @ActionArgs, $Mapping
                        }
                    }
                }
            }
        }
        elsif (@DescendantSourcePaths)
        {
            if ($Change eq 'A' or $Change eq 'R')
            {
                my (@ImplicitlyAddedPaths, @ImplicitlyDeletedPaths);

                for my $ImplicitlyChangedPath (@DescendantSourcePaths)
                {
                    eval
                    {
                        $SVN->ReadInfo($RootURL .
                            "/$ImplicitlyChangedPath\@$RevisionNumber")
                    };
                    unless ($@)
                    {
                        push @ImplicitlyAddedPaths, $ImplicitlyChangedPath
                    }
                    elsif ($Change eq 'R')
                    {
                        push @ImplicitlyDeletedPaths, $ImplicitlyChangedPath
                    }
                }
print " $Change $ChangedSourcePath  : Ancestor of '@DescendantSourcePaths'\n";
print "   actually changed '".join("', '",@ImplicitlyAddedPaths)."'\n" if @ImplicitlyAddedPaths;

                if (@ImplicitlyAddedPaths || @ImplicitlyDeletedPaths)
                {
                    push @ActionArgs, \@ImplicitlyAddedPaths;
                    push @RequireParentsFor, \@ImplicitlyAddedPaths;

                    if ($Change eq 'A')
                    {
                        $Action = 'AddPathPerAncestorAddition'
                    }
                    else # $Change is 'R'.
                    {
                        $Action = 'ReplacePathPerAncestorReplacement';

                        push @ActionArgs, \@ImplicitlyDeletedPaths
                    }

                    if ($CopyFromSourcePath)
                    {
                        $Action .= 'ByCopying';

                        push @ActionArgs, $CopyFromSourcePath, $CopyFromSourceRev
                    }
                }
else {print "                  ...ignored...\n"}
            }
            elsif ($Change eq 'D')
            {
                $Action = 'DeletePathPerAncestorDeletion';

                push @ActionArgs, \@DescendantSourcePaths
            }
            # Ignore localized ancestor modifications ($Change is 'M').
        }
        else
        {
            # The changed path is neither a descendant nor an
            # ancestor of any of the source paths, skip it.
            next
        }

        next unless $Action;

        unless ($Changed)
        {
            $Changed = 1;

            print '-' x 80 . "\nApplying revision $RevisionNumber of '" .
                $SourceRepoConf->{RepoName} . "'...\n";

            $SVN->RunSubversion(qw(update --ignore-externals));

            print "Checking for uncommitted changes...\n";

            my @LocalChanges = grep(!m/^X/o, $SVN->ReadSubversionLines(
                qw(status --ignore-externals)));

            if (@LocalChanges)
            {
                local $" = "\n  ";
                die "Error: uncommitted changes detected:\n  @LocalChanges\n"
            }

            $DiscardSvnExternals = $SourceRepoConf->{DiscardSvnExternals}
        }

        for (@RequireParentsFor)
        {
            my ($ParentDir) = m/(.*)\//so;

            if ($ParentDir && !-d $ParentDir)
            {
                print "Creating missing parent directory $ParentDir...\n";
                $SVN->RunSubversion(qw(mkdir --parents), $ParentDir)
            }
        }

print "[$Action]\n";
        $Self->$Action(@ActionArgs)
    }

    if ($Changed)
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

    return $Changed
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

sub BuildTree
{
    my ($Self, $Paths, $PathType) = @_;

    my $Root = {};

    for my $Path (@$Paths)
    {
        ref($Root) eq 'HASH' or die "$Self->{MyName}: cannot " .
            "combine an empty path with other $PathType paths.\n";

        my $NodeRef = \$Root;

        for my $Dir (split('/', $Path))
        {
            next unless $Dir;

            ref($$NodeRef) eq 'HASH' or die "$Self->{MyName}: " .
                "$PathType paths '$Path' and '$$NodeRef' overlap.\n";

            $NodeRef = \(${$NodeRef}->{$Dir} ||= {})
        }

        if (%$$NodeRef)
        {
            die "$Self->{MyName}: $PathType path " .
                "'$Path' overlaps other path(s).\n"
        }

        $$NodeRef = $Path
    }

    return $Root
}

sub RequireParam
{
    my ($Self, $Hash, $ParamName) = @_;

    my $Value = $Hash->{$ParamName};
    if (!defined $Value || (ref($Value) eq 'ARRAY' && @$Value == 0))
    {
        die "$Self->{MyName}: missing required parameter '$ParamName'.\n"
    }

    return $Value
}

sub LoadConf
{
    my ($Self, $ConfFile) = @_;

    my $Conf = do $ConfFile;

    unless (ref($Conf) eq 'HASH')
    {
        die "$Self->{MyName}: $@\n" if $@;
        die "$Self->{MyName}: $ConfFile\: $!\n" unless defined $Conf;
        die "$Self->{MyName}: configuration file " .
            "'$ConfFile' must return a hash\n"
    }

    $Self->RequireParam($Conf, 'TargetWorkingCopy');

    my $SourceRepositories = $Self->RequireParam($Conf, 'SourceRepositories');

    my @TargetPaths;

    for my $SourceRepoConf (@$SourceRepositories)
    {
        $Self->RequireParam($SourceRepoConf, 'RepoName');
        $Self->RequireParam($SourceRepoConf, 'RootURL');

        my @SourcePaths;
        my @RepoTargetPaths;

        if ($SourceRepoConf->{TargetPath})
        {
            $SourceRepoConf->{PathMapping} = [{SourcePath => '',
                TargetPath => $SourceRepoConf->{TargetPath},
                ExclusionList => $SourceRepoConf->{ExclusionList}}]
        }

        my $PathMapping = $Self->RequireParam($SourceRepoConf, 'PathMapping');

        my $SourcePathToMapping = $SourceRepoConf->{SourcePathToMapping} = {};

        for my $Mapping (@$PathMapping)
        {
            my $SourcePath = $Self->RequireParam($Mapping, 'SourcePath');
            push @SourcePaths, $SourcePath;

            $SourcePathToMapping->{$SourcePath} = $Mapping;

            my $TargetPath = $Self->RequireParam($Mapping, 'TargetPath');
            push @TargetPaths, $TargetPath;
            push @RepoTargetPaths, $TargetPath;

            if ($Mapping->{ExclusionList})
            {
                $Mapping->{ExclusionTree} =
                    $Self->BuildTree($Mapping->{ExclusionList}, 'exclusion')
            }
        }

        $SourceRepoConf->{SourcePathTree} =
            $Self->BuildTree(\@SourcePaths, 'source');

        $SourceRepoConf->{TargetPathTree} =
            $Self->BuildTree(\@RepoTargetPaths, 'target');

        $SourceRepoConf->{TargetPaths} = \@RepoTargetPaths
    }

    $Conf->{TargetPathTree} = $Self->BuildTree(\@TargetPaths, 'target');

    $Conf->{TargetPaths} = \@TargetPaths;

    return $Conf
}

sub Run
{
    my ($Self, $ConfFile) = @_;

    my $Conf = $Self->LoadConf($ConfFile);

    my $SVN = $Self->{SVN};

    if ($CommitCredentials = $Conf->{CommitCredentials})
    {
        $CommitCredentials = ref $CommitCredentials ?
            ['--username', $CommitCredentials->[0],
                '--password', $CommitCredentials->[1]] :
            ['--username', $CommitCredentials]
    }

    chdir $Conf->{TargetWorkingCopy} or
        die "$Self->{MyName}: could not chdir to $Conf->{TargetWorkingCopy}.\n";

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
        $ChangesApplied += $Self->ApplyRevisionChanges($SVN, shift @$Revisions);

        PushRevisionArray(\@RevisionArrayHeap, $Revisions) if @$Revisions
    }

    print $LineContinuation . ($ChangesApplied ?
        "$ChangesApplied change(s) applied.\n" : "no relevant changes.\n");

    return 0
}

sub Init
{
    my ($Self, $InitPath, $ConfFile) = @_;

    if (-d $InitPath)
    {
        die "$Self->{MyName}: cannot create repository: " .
            "$InitPath already exists.\n"
    }

    my $Conf = $Self->LoadConf($ConfFile);

    my $TargetWorkingCopy = $Conf->{TargetWorkingCopy};

    if (-d $TargetWorkingCopy)
    {
        die "$Self->{MyName}: error: the workinig copy " .
            "directory '$TargetWorkingCopy' already exists.\n"
    }

    my $SVN = $Self->{SVN};

    my $EarliestRevisionTime;

    print "Picking the earliest revision date...\n";

    for my $SourceRepoConf (@{$Conf->{SourceRepositories}})
    {
        my $InitialRevisionTime = $SVN->ReadRevProps(0,
            $SourceRepoConf->{RootURL})->{'svn:date'};

        unless ($EarliestRevisionTime)
        {
            $EarliestRevisionTime = $InitialRevisionTime
        }
        elsif ($EarliestRevisionTime gt $InitialRevisionTime)
        {
            $EarliestRevisionTime = $InitialRevisionTime
        }
    }

    die unless $EarliestRevisionTime;

    print "Creating a new repository...\n";

    $SVN->RunOrDie(qw(svnadmin create), $InitPath);

    print "Installing a dummy pre-revprop-change hook script...\n";

    my $HookScript = "$InitPath/hooks/pre-revprop-change";

    open HOOK, '>', $HookScript or die "$HookScript: $!\n";
    print HOOK "#!/bin/sh\n\nexit 0\n";
    close HOOK;
    chmod 0755, $HookScript or die "$HookScript: $!\n";

    require File::Spec;

    my $URL = 'file://' . File::Spec->rel2abs($InitPath);

    print "Setting svn:date...\n";

    $SVN->RunSubversion(qw(propset --revprop -r0 svn:date),
        $EarliestRevisionTime, $URL);

    print "Checking out revision 0...\n";

    $SVN->RunSubversion('checkout', $URL, $TargetWorkingCopy);

    return 0
}

1
