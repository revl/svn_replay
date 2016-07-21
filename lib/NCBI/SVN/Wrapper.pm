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

package NCBI::SVN::Wrapper::Stream;

use IPC::Open3;
use File::Temp qw/tempfile/;
use File::Spec;

sub new
{
    my ($Class, $SVN) = @_;

    return bless {SVN => $SVN}, $Class
}

sub Run
{
    my ($Self, @Args) = @_;

    my $WriteFH;

    unshift @Args, '--non-interactive' unless grep {m/^add$/o} @Args;

    $Self->{PID} = open3($WriteFH, $Self->{ReadFH},
        $Self->{ErrorFH} = tempfile(),
        $Self->{SVN}->GetSvnPathname(), @Args);

    close $WriteFH
}

sub ReadLine
{
    return readline $_[0]->{ReadFH}
}

sub Close
{
    my ($Self) = @_;

    return unless exists $Self->{PID};

    local $/ = undef;
    my $ErrorText = readline $Self->{ErrorFH};

    close($Self->{ReadFH});
    close($Self->{ErrorFH});

    waitpid(delete $Self->{PID}, 0);

    die $ErrorText if $?
}

package NCBI::SVN::Wrapper;

use Carp qw(confess);
use Time::Local;

sub FindProgram
{
    my ($Path, @Names) = @_;

    for my $Program (@Names)
    {
        my $Pathname = File::Spec->catfile($Path, $Program);

        return $Pathname if -f $Pathname
    }

    return undef
}

sub FindSubversion
{
    my ($Self) = @_;

    my ($SvnMUCCName, $MUCCName, @SvnNames) =
        !$Self->{Windows} ? qw(svnmucc mucc svn) :
            qw(svnmucc.exe mucc.exe svn.bat svn.exe);

    my ($SvnPathname, $SvnMUCCPathname, $MUCCPathname);

    for my $Path (File::Spec->path())
    {
        $SvnPathname ||= FindProgram($Path, @SvnNames);
        $SvnMUCCPathname ||= FindProgram($Path, $SvnMUCCName);
        $MUCCPathname ||= FindProgram($Path, $MUCCName);

        last if $SvnMUCCPathname && $SvnPathname
    }

    confess('Unable to find "svn" in PATH') unless $SvnPathname;

    @$Self{qw(SvnPathname MUCCPathname)} =
        ($SvnPathname, ($SvnMUCCPathname || $MUCCPathname))
}

sub new
{
    my ($Class, @Params) = @_;

    my $Self = bless {@Params}, $Class;

    $Self->{MyName} ||= $Class;

    $Self->{Windows} = 1 if $^O eq 'MSWin32' || $^O eq 'cygwin';

    $Self->FindSubversion() unless $Self->{SvnPathname};

    return $Self
}

sub SetSvnPathname
{
    my ($Self, $Pathname) = @_;

    $Self->{SvnPathname} = $Pathname
}

sub GetSvnPathname
{
    my ($Self) = @_;

    return $Self->{SvnPathname}
}

sub SetMUCCPathname
{
    my ($Self, $Pathname) = @_;

    $Self->{MUCCPathname} = $Pathname
}

sub GetMUCCPathname
{
    my ($Self) = @_;

    return $Self->{MUCCPathname}
}

sub GetRootURL
{
    my ($Self, $Path) = @_;

    $Path ||= '.';

    return -d '.svn' ? $Self->ReadInfo($Path)->{$Path}->{Root} : undef
}

sub RunOrDie
{
    my ($Self, @CommandAndParams) = @_;

    if (system(@CommandAndParams) != 0)
    {
        my $CommandLine = join(' ', @CommandAndParams);

        die "$Self->{MyName}: " .
            ($? == -1 ? "failed to execute $CommandLine\: $!" :
            $? & 127 ? "'$CommandLine' died with signal " . ($? & 127) :
            "'$CommandLine' exited with status " . ($? >> 8)) . "\n"
    }
}

sub RunSubversion
{
    my ($Self, @Params) = @_;

    $Self->RunOrDie($Self->GetSvnPathname(), @Params)
}

sub RunMUCC
{
    my ($Self, @Params) = @_;

    $Self->RunOrDie(($Self->GetMUCCPathname() or
        confess('Unable to find "svnmucc" or "mucc" in PATH')), @Params)
}

sub Run
{
    my ($Self, @Args) = @_;

    my $Stream = NCBI::SVN::Wrapper::Stream->new($Self);

    $Stream->Run(@Args);

    return $Stream
}

sub ReadFile
{
    my ($Self, @Args) = @_;

    return $Self->ReadSubversionStream('cat', @Args)
}

sub ReadFileLines
{
    my ($Self, @Args) = @_;

    return $Self->ReadSubversionLines('cat', @Args)
}

sub ReadInfo
{
    my ($Self, @Args) = @_;

    my $Stream = $Self->Run('info', @Args);

    my %Info;
    my $Path;
    my $Line;

    while (defined($Line = $Stream->ReadLine()))
    {
        $Line =~ s/[\r\n]+$//so;

        if ($Line =~ m/^Path: (.*?)$/os)
        {
            $Path = $1;
            $Path =~ s/\\/\//gso if $Self->{Windows}
        }
        elsif ($Line =~ m/^URL: (.*?)$/os)
        {
            $Info{$Path}->{Path} = $1
        }
        elsif ($Line =~ m/^Repository Root: (.*?)$/os)
        {
            $Info{$Path}->{Root} = $1
        }
        elsif (my ($Key, $Value) = $Line =~ m/^(.+?): (.*?)$/os)
        {
            $Key =~ s/ //go;
            $Info{$Path}->{$Key} = $Value
        }
    }

    my $Root;

    for my $PathInfo (values %Info)
    {
        ($Root, $Path) = @$PathInfo{qw(Root Path)};

        substr($Path, 0, length($Root), '') eq $Root or die;

        $PathInfo->{Path} = length($Path) > 0 ?
            substr($Path, 0, 1, '') eq '/' ? $Path : die : '.'
    }

    $Stream->Close();

    return \%Info
}

# This method is deprecated -- it cannot be used to get
# properties at a specific revision. ReadPathProps() must
# be used instead.
sub ReadProps
{
    my ($Self, @Paths) = @_;

    my $Stream = $Self->Run('proplist', @Paths);

    my %Props;
    my $Path;
    my $Line;

    while (defined($Line = $Stream->ReadLine()))
    {
        $Line =~ s/[\r\n]+$//so;

        if ($Line =~ m/^Properties on '(.+)':$/o)
        {
            $Path = $1
        }
        elsif ($Line =~ m/^\s+(.+)$/o)
        {
            chomp($Props{$Path}->{$1} = $Self->ReadSubversionStream(
                'propget', $1, $Path))
        }
        else
        {
            die 'Unexpected proplist output'
        }
    }

    $Stream->Close();

    return \%Props
}

sub ReadPropsImpl
{
    my ($Self, $HeaderPattern, @Args) = @_;

    my %Props;

    my $Stream = $Self->Run('proplist', @Args);

    my $Header = $Stream->ReadLine();

    if ($Header)
    {
        $Header =~ $HeaderPattern or die 'Invalid proplist output';

        my $Line;

        while (defined($Line = $Stream->ReadLine()))
        {
            $Line =~ s/[\r\n]+$//so;

            $Line =~ m/^\s+(.+?)$/so or die 'Unexpected proplist output';

            chomp($Props{$1} =
                $Self->ReadSubversionStream('propget', $1, @Args))
        }
    }

    $Stream->Close();

    return \%Props
}

sub ReadPathProps
{
    my ($Self, $Path, $Revision) = @_;

    return $Self->ReadPropsImpl('^Properties on',
        $Revision ? ('-r', $Revision, $Path . '@' . $Revision) : ($Path))
}

sub ReadRevProps
{
    my ($Self, $Revision, @URL) = @_;

    return $Self->ReadPropsImpl('^Unversioned properties on revision',
        qw(--revprop -r), $Revision, @URL)
}

sub LogParsingError
{
    my ($Stream, $CurrentRevision, $State, $Line) = @_;

    local $/ = undef;
    $Stream->ReadLine();
    $Stream->Close();

    my $ErrorMessage = "svn log parsing error: state: $State; line '$Line'";

    $ErrorMessage .= "; r$CurrentRevision->{Number}" if $CurrentRevision;

    confess "$ErrorMessage\n"
}

sub IsLogSeparator
{
    return $_[0] =~ m/^-{70}/o
}

sub ReadLog
{
    my ($Self, @LogParams) = @_;

    my $Stream = $Self->Run('log', '--verbose', @LogParams);

    my $Line;
    my $State = 'initial';

    my @Revisions;
    my $CurrentRevision;
    my $SeparatorOrLogLine;

    while (defined($Line = $Stream->ReadLine()))
    {
        $Line =~ s/[\r\n]+$//;

        if ($State eq 'changed_path')
        {
            if ($Line)
            {
                $Line =~ m/^   ([AMDR]) (.+?)(?: \(from (.+):(\d+)\))?$/o or
                    LogParsingError($Stream, $CurrentRevision, $State, $Line);

                push @{$CurrentRevision->{ChangedPaths}}, [$1, $2, $3, $4]
            }
            else
            {
                $State = 'log_message';
            }
        }
        elsif ($State eq 'log_message')
        {
            if (IsLogSeparator($Line))
            {
                $SeparatorOrLogLine = $Line;
                $State = 'revision_header'
            }
            else
            {
                $CurrentRevision->{LogMessage} .= $Line . "\n"
            }
        }
        elsif ($State eq 'revision_header')
        {
            unless ($Line =~ m/^r\d+ \|/)
            {
                $CurrentRevision->{LogMessage} .= "$SeparatorOrLogLine\n";

                if (IsLogSeparator($Line))
                {
                    $SeparatorOrLogLine = $Line
                }
                else
                {
                    $CurrentRevision->{LogMessage} .= $Line . "\n";
                    $State = 'log_message'
                }

                next
            }

            my %NewRev = (LogMessage => '', ChangedPaths => []);

            push @Revisions, ($CurrentRevision = \%NewRev);

            my $Time;

            (@NewRev{qw(Number Author)}, $Time) = $Line =~
                m/^r(\d+) \| (.+?) \| (.+?) \(.+?\) \| \d+ lines?$/o or
                    LogParsingError($Stream, $CurrentRevision, $State, $Line);

            my ($Year, $Month, $Day, $Hour, $Min, $Sec) =
                $Time =~ m/^(....)-(..)-(..) (..):(..):(..)/o;

            ($Sec, $Min, $Hour, $Day, $Month, $Year) = gmtime(timelocal($Sec,
                $Min, $Hour, $Day, $Month - 1, $Year - 1900));

            $NewRev{Time} = sprintf('%4d-%02d-%02dT%02d:%02d:%02d.000000Z',
                $Year + 1900, $Month + 1, $Day, $Hour, $Min, $Sec);

            $State = 'changed_path_header'
        }
        elsif ($State eq 'changed_path_header')
        {
            if ($Line eq 'Changed paths:')
            {
                $State = 'changed_path'
            }
            elsif ($Line eq '')
            {
                $State = 'log_message'
            }
            else
            {
                LogParsingError($Stream, $CurrentRevision, $State, $Line)
            }
        }
        elsif ($State eq 'initial')
        {
            LogParsingError($Stream, $CurrentRevision, $State, $Line)
                unless IsLogSeparator($Line);

            $State = 'revision_header'
        }
    }

    $Stream->Close();

    for my $Revision (@Revisions)
    {
        $Revision->{LogMessage} =~ s/[\r\n]+$//so;
        $Revision->{LogMessage} =~ s/\r\n/\n/gso;
        $Revision->{LogMessage} =~ s/\r/\n/gso
    }

    return \@Revisions;
}

sub GetLatestRevision
{
    my ($Self, $URL) = @_;

    my $Stream = $Self->Run('info', $URL);

    my $Line;
    my $Revision;

    while (defined($Line = $Stream->ReadLine()))
    {
        if ($Line =~ m/^Revision: (\d+)/os)
        {
            $Revision = $1;
            last
        }
    }

    local $/ = undef;
    $Stream->ReadLine();
    $Stream->Close();

    return $Revision
}

sub ReadSubversionStream
{
    my ($Self, @CommandAndParams) = @_;

    my $Stream = $Self->Run(@CommandAndParams);

    local($/) = undef;

    my $Contents = $Stream->ReadLine();

    $Stream->Close();

    return $Contents
}

sub ReadSubversionLines
{
    my ($Self, @CommandAndParams) = @_;

    my $Stream = $Self->Run(@CommandAndParams);

    my @Lines;
    my $Line;

    while (defined($Line = $Stream->ReadLine()))
    {
        $Line =~ s/[\r\n]+$//so;
        push @Lines, $Line
    }

    $Stream->Close();

    return @Lines
}

1

# vim: filetype=perl tabstop=4 shiftwidth=4 softtabstop=4 expandtab
