package NCBI::SVN::Replay;

use strict;
use warnings;

use base qw(NCBI::SVN::Base);

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
                qw(pg --non-interactive --revprop ncbi:original-revision -r),
                    $RevisionNumber, $URL);

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

sub ApplyRevisionChanges
{
    my ($SVN, $Revision) = @_;

    my ($SourceRepoConf, $RevisionNumber) =
        @$Revision{qw(SourceRepoConf Number)};

    my ($RootURL, $RepoName, $SourcePathFilter,
        $PathnameTransform, $TargetPath, $TargetPathInfo) =
            @$SourceRepoConf{qw(RootURL RepoName SourcePathFilter
                PathnameTransform TargetPath TargetPathInfo)};

    my $Changed = 0;

    print "Applying r$RevisionNumber of $RepoName...\n";

    # Sort changes by the change type (Add first, then Delete)
    # sort {$a->[0] cmp $b->[0]}
    for (@{$Revision->{ChangedPaths}})
    {
        my ($Change, $Path, $SourcePath, $SourceRev) = @$_;

        next unless $SourcePathFilter->($Path);

        unless ($Changed)
        {
            $Changed = 1;

            $SVN->RunSubversion(
                qw(update --ignore-externals --non-interactive), $TargetPath)
        }

        my $TargetFilePathname = $Path;

        $PathnameTransform->($TargetFilePathname);

        $TargetFilePathname = "$TargetPath/$TargetFilePathname";

        my $ResetProps;

        if ($Change eq 'A')
        {
            if ($SourcePath && $SourcePathFilter->($SourcePath))
            {
                my $SourceFilePathname = $SourcePath;

                $PathnameTransform->($SourceFilePathname);

                $SourceFilePathname = "$TargetPath/$SourceFilePathname";

                $SourceRev = FindSourceRev($SVN, $SourceRev,
                    "$TargetPathInfo->{Root}/$TargetPath");

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
        my $Output = $SVN->ReadSubversionStream(qw(commit --non-interactive -m),
            $Revision->{LogMessage}, '--username', 'syncbot', $TargetPath);

        my ($NewRevision) = $Output =~ m/Committed revision (\d+)\./o;

        if ($NewRevision)
        {
            print $Output;

            $SVN->RunSubversion(qw(propset --non-interactive --revprop
                ncbi:original-revision -r), $NewRevision, $RevisionNumber);

            my $RevProps = $SVN->ReadRevProps($RevisionNumber,
                '--non-interactive', $RootURL);

            while (my ($Name, $Value) = each %$RevProps)
            {
                next if $Name eq 'svn:log';

                $SVN->RunSubversion(
                    qw(ps --non-interactive --username syncbot --revprop -r),
                        $NewRevision, $Name, $Value)
            }
        }
        else
        {
            print "WARNING: no changes detected.\n"
        }
    }
    else
    {
        print $LineContinuation . "skipped.\n"
    }
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

    my $SourceRepositories = $Conf->{SourceRepositories};

    my @TargetPaths = map {$_->{TargetPath}} @$SourceRepositories;

    if (@TargetPaths == 0)
    {
        die "$Self->{MyName}: at least one target path must be specified.\n"
    }

    # Check for target path conflicts.
    unless ($Conf->{AllowTargetPathOverlap})
    {
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
    }

    chdir $Conf->{TargetWorkingCopy};

    $SVN->RunSubversion(qw(update --ignore-externals --non-interactive),
        @TargetPaths);

    my $TargetPathInfo = $SVN->ReadInfo(@TargetPaths);

    my @RevisionArrayHeap;

    for my $SourceRepoConf (@$SourceRepositories)
    {
        my $TargetPath = $SourceRepoConf->{TargetPath};

        my $Info = $TargetPathInfo->{$TargetPath}
            or die "$Self->{MyName}: could not get svn info on $TargetPath.\n";

        $SourceRepoConf->{TargetPathInfo} = $Info;

        my $LastOriginalRev = $SVN->ReadSubversionStream(
            qw(propget --non-interactive --revprop ncbi:original-revision -r),
                $Info->{LastChangedRev}, $TargetPath) || 0;

        chomp $LastOriginalRev;

        my $RootURL = $SourceRepoConf->{RootURL};

        my ($RepoName) = $RootURL =~ m/([^\/]*)$/o;

        $SourceRepoConf->{RepoName} = $RepoName;

        print "Reading what's new in $RepoName since r$LastOriginalRev...\n";

        my $Revisions = eval {$SVN->ReadLog('--non-interactive',
            '-rHEAD:' . ($LastOriginalRev + 1), $RootURL)} || [];

        if ($@)
        {
            print "WARNING: error while reading revision log: $@\n"
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

    while (my $Revisions = PopRevisionArray(\@RevisionArrayHeap))
    {
        ApplyRevisionChanges($SVN, shift @$Revisions);

        PushRevisionArray(\@RevisionArrayHeap, $Revisions) if @$Revisions
    }

    return 0
}

1
