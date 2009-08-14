package NCBI::SVN::Replay;

use strict;
use warnings;

use base qw(NCBI::SVN::Base);

my $CommitCredentials;
my $OriginalRevPropName = 'ncbi:original-revision';

my $LineContinuation = '  ... ';

sub IsFile
{
    my ($SVN, $RevisionNumber, $Path) = @_;

    my ($Info) = values %{$SVN->ReadInfo(qw(--non-interactive -r),
        $RevisionNumber, $Path . '@' . $RevisionNumber)};

    my $NodeKind = $Info->{NodeKind};

    return $NodeKind eq 'file' ? 1 : $NodeKind eq 'directory' ?
        0 : die "Unknown node kind '$NodeKind'\n"
}

sub DownloadFile
{
    my ($SVN, $RevisionNumber, $URL, $TargetFilePathname) = @_;

    my $Contents = $SVN->ReadFile(qw(--non-interactive -r),
        $RevisionNumber, $URL . '@' . $RevisionNumber);

    open FILE, '>', $TargetFilePathname or die "$TargetFilePathname\: $!\n";
    syswrite FILE, $Contents;
    close FILE
}

my $LogChunkSize = 100;

sub FindSourceRev
{
    my ($SVN, $SourceRev, $URL) = @_;

    my $Revisions = $SVN->ReadLog(qw(--non-interactive --limit),
        $LogChunkSize, $URL);

    for (;;)
    {
        my $RevisionNumber = 0;

        for my $Revision (@$Revisions)
        {
            $RevisionNumber = $Revision->{Number};

            my $OriginalRev = $SVN->ReadSubversionStream(
                qw(pg --non-interactive --revprop -r),
                    $RevisionNumber, $OriginalRevPropName, $URL);

            die "Could not get original revision for $SourceRev\n"
                unless $OriginalRev;

            chomp $OriginalRev;

            if ($OriginalRev <= $SourceRev)
            {
                print "WARNING: using older original revision $OriginalRev\n"
                    if $OriginalRev < $SourceRev;

                return $RevisionNumber
            }
        }

        --$RevisionNumber;

        for (;;)
        {
            die "Could not find revision by original revision $SourceRev.\n"
                if $RevisionNumber <= 0;

            my $Bound = $RevisionNumber > $LogChunkSize ?
                $RevisionNumber - $LogChunkSize + 1 : 1;

            $Revisions = $SVN->ReadLog(qw(--non-interactive -r),
                $RevisionNumber . ':' . $Bound, $URL);

            last if @$Revisions;

            $RevisionNumber = $Bound - 1
        }
    }
}

my $TargetPathInfo;

sub TransformPath
{
    my ($RepoConf, $Path) = @_;

    $RepoConf->{PathnameTransform}->($Path);

    for my $TargetDirectory (@{$RepoConf->{TargetPaths}})
    {
        return ($Path, $TargetDirectory)
            if substr($Path, 0, length($TargetDirectory)) eq $TargetDirectory
    }

    die "Transformed path $Path does not match any of the target directories.\n"
}

sub ApplyRevisionChanges
{
    my ($SVN, $Revision) = @_;

    my ($SourceRepoConf, $RevisionNumber) =
        @$Revision{qw(SourceRepoConf Number)};

    my ($RootURL, $SourcePathFilter) =
        @$SourceRepoConf{qw(RootURL SourcePathFilter)};

    my $Changed = 0;

    # Sort changes by the change type (Add first, then Delete)
    # sort {$a->[0] cmp $b->[0]}
    for (@{$Revision->{ChangedPaths}})
    {
        my ($Change, $Path, $SourcePath, $SourceRev) = @$_;

        next unless $SourcePathFilter->($Path);

        unless ($Changed)
        {
            $Changed = 1;

            print "Applying r$RevisionNumber of the '" .
                $SourceRepoConf->{RepoName} . "' repository ...\n";

            $SVN->RunSubversion(qw(update --ignore-externals --non-interactive),
                @{$SourceRepoConf->{TargetPaths}})

            my @LocalChanges = grep(!m/^X/o, $SVN->ReadSubversionLines(
                qw(status --ignore-externals --non-interactive),
                    @{$SourceRepoConf->{TargetPaths}}));

            if (@LocalChanges)
            {
                local $" = "\n  ";
                die "Error: local changes detected:$"@LocalChanges\n"
            }
        }

        my ($TargetFilePathname) = TransformPath($SourceRepoConf, $Path);

        my $ResetProps;

        if ($Change eq 'A')
        {
            if ($SourcePath && $SourcePathFilter->($SourcePath))
            {
                my ($SourceFilePathname, $TargetPath) =
                    TransformPath($SourceRepoConf, $SourcePath);

                $SourceRev = FindSourceRev($SVN, $SourceRev,
                    $TargetPathInfo->{$TargetPath}->{Root} . '/' . $TargetPath);

                print $LineContinuation . 'cp -r ' .
                    "$SourceRev $SourceFilePathname $TargetFilePathname\n";

                $SVN->RunSubversion(qw(cp --non-interactive -r),
                    $SourceRev, $SourceFilePathname, $TargetFilePathname)
            }
            else
            {
                if (IsFile($SVN, $RevisionNumber, $RootURL . $Path))
                {
                    DownloadFile($SVN, $RevisionNumber,
                        $RootURL . $Path, $TargetFilePathname);

                    $SVN->RunSubversion(qw(add --no-auto-props),
                        $TargetFilePathname)
                }
                else
                {
                    eval
                    {
                        $SVN->RunSubversion(qw(mkdir --non-interactive),
                            $TargetFilePathname)
                    };
                    if ($@)
                    {
                        print 'WARNING: Could not mkdir ' .
                            $TargetFilePathname . ": $@\n"
                    }
                }

                $ResetProps = 1
            }
        }
        elsif ($Change eq 'M')
        {
            if (IsFile($SVN, $RevisionNumber, $RootURL . $Path))
            {
                DownloadFile($SVN, $RevisionNumber,
                    $RootURL . $Path, $TargetFilePathname)
            }

            $ResetProps = 1
        }
        elsif ($Change eq 'D')
        {
            $SVN->RunSubversion(qw(rm --non-interactive),
                $TargetFilePathname)
        }
        else
        {
            die "Unknown change type '$Change' in " .
                "r$RevisionNumber of $RootURL\n"
        }

        if ($ResetProps)
        {
            my ($OldProps) = values %{$SVN->ReadProps('--non-interactive',
                $TargetFilePathname)};

            my ($Props) = values %{$SVN->ReadProps(qw(--non-interactive -r),
                $RevisionNumber, "$RootURL$Path\@$RevisionNumber")};

            delete $Props->{'svn:externals'} if $RepoConf->{DiscardSvnExternals};

            while (my ($Name, $Value) = each %$Props)
            {
                $SVN->RunSubversion(qw(propset --non-interactive),
                    $Name, $Value, $TargetFilePathname)
                        if !defined($OldProps->{$Name}) ||
                            $Value ne $OldProps->{$Name}
            }

            while (my ($Name, $Value) = each %$OldProps)
            {
                $SVN->RunSubversion(qw(propdel --non-interactive),
                    $Name, $TargetFilePathname)
                        if !defined($Props->{$Name})
            }
        }
    }

    if ($Changed)
    {
        my @AuthParams = $CommitCredentials ? @$CommitCredentials :
            ('--username', $Revision->{Author});

        my $Output = $SVN->ReadSubversionStream(@AuthParams,
            qw(commit --non-interactive -m),
                $Revision->{LogMessage}, @{$SourceRepoConf->{TargetPaths}});

        my ($NewRevision) = $Output =~ m/Committed revision (\d+)\./o;

        if ($NewRevision)
        {
            print $Output;

            my $RevProps = $SVN->ReadRevProps($RevisionNumber,
                '--non-interactive', $RootURL);

            delete $RevProps->{'svn:log'};
            delete $RevProps->{'svn:author'} unless $CommitCredentials;

            $RevProps->{$OriginalRevPropName} = $RevisionNumber;

            while (my ($Name, $Value) = each %$RevProps)
            {
                $SVN->RunSubversion(@AuthParams,
                    qw(ps --non-interactive --revprop -r),
                        $NewRevision, $Name, $Value)
            }
        }
        else
        {
            print "WARNING: no changes detected.\n"
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

sub Run
{
    my ($Self, $Conf) = @_;

    my $SVN = $Self->{SVN};

    if ($CommitCredentials = $Conf->{CommitCredentials})
    {
        $CommitCredentials = ref $CommitCredentials ?
            ['--username', $CommitCredentials->[0],
                '--password', $CommitCredentials->[1]] :
            ['--username', $CommitCredentials]
    }

    my $SourceRepositories = $Conf->{SourceRepositories};

    if (@$SourceRepositories == 0)
    {
        die "$Self->{MyName}: missing required parameter SourceRepositories.\n"
    }

    my @TargetPaths;

    for my $SourceRepoConf (@$SourceRepositories)
    {
        unless ($SourceRepoConf->{TargetPaths})
        {
            $SourceRepoConf->{TargetPaths} = [$SourceRepoConf->{TargetPath} or
                die "$Self->{MyName}: missing required " .
                    "parameter TargetPath(s).\n"]
        }
        elsif ($SourceRepoConf->{TargetPath})
        {
            die "$Self->{MyName}: parameters TargetPath and " .
                "TargetPaths are mutually exclusive.\n"
        }
        push @TargetPaths, @{$SourceRepoConf->{TargetPaths}}
    }

    # Check for target path conflicts.
    my %VerificationTree;

    for my $Path (@TargetPaths)
    {
        my $SubTree = \%VerificationTree;

        for my $Dir (split('/', $Path))
        {
            if ($SubTree->{'/'})
            {
                die "$Self->{MyName}: target path conflict: " .
                    "'$SubTree->{'/'}' includes '$Path'.\n"
            }

            $SubTree = ($SubTree->{$Dir} ||= {})
        }

        if (%$SubTree)
        {
            die "$Self->{MyName}: target path '$Path' overlaps other path(s).\n"
        }

        $SubTree->{'/'} = $Path
    }

    chdir $Conf->{TargetWorkingCopy} or
        die "$Self->{MyName}: could not chdir to $Conf->{TargetWorkingCopy}.\n";

    $SVN->RunSubversion(qw(update --ignore-externals --non-interactive),
        @TargetPaths);

    $TargetPathInfo = $SVN->ReadInfo(@TargetPaths);

    my @RevisionArrayHeap;

    for my $SourceRepoConf (@$SourceRepositories)
    {
        my $LastOriginalRev = 0;

        for my $TargetPath (@{$SourceRepoConf->{TargetPaths}})
        {
            my $Info = $TargetPathInfo->{$TargetPath}
                or die "$Self->{MyName}: could not get svn info on '$TargetPath'.\n";

            my $OriginalRev = $SVN->ReadSubversionStream(
                qw(pg --non-interactive --revprop -r),
                    $Info->{LastChangedRev}, $OriginalRevPropName, $TargetPath);

            chomp $OriginalRev;

            if ($OriginalRev eq '')
            {
                die "Revision property '$OriginalRevPropName' is not set for r" .
                    $Info->{LastChangedRev} . ".\n"
            }

            $LastOriginalRev = $OriginalRev if $LastOriginalRev < $OriginalRev
        }

        my $RootURL = $SourceRepoConf->{RootURL};

        my ($RepoName) = $RootURL =~ m/([^\/]*)$/o;

        $SourceRepoConf->{RepoName} = $RepoName;

        print "Reading what's new in the '$RepoName' " .
            "repository since r$LastOriginalRev...\n";

        my $Revisions = $SVN->ReadLog('--non-interactive',
            '-rHEAD:' . $LastOriginalRev, $RootURL);

        pop(@$Revisions)->{Number} == $LastOriginalRev or die 'Logic error';

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
        $ChangesApplied += ApplyRevisionChanges($SVN, shift @$Revisions);

        PushRevisionArray(\@RevisionArrayHeap, $Revisions) if @$Revisions
    }

    print $LineContinuation . ($ChangesApplied ?
        "$ChangesApplied change(s) applied.\n" : "no relevant changes.\n");

    return 0
}

1
