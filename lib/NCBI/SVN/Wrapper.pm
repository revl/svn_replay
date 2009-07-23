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

    $Self->{PID} = open3($WriteFH, $Self->{ReadFH},
        $Self->{ErrorFH} = tempfile(),
        $Self->{SVN}->GetSvnPathname(), '--non-interactive', @Args);

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

sub ReadProps
{
    my ($Self, @Args) = @_;

    my $Stream = $Self->Run(qw(proplist --verbose), @Args);

    my %Props;
    my $Path;
    my $PropName;
    my $PropValue;
    my $Line;

    while (defined($Line = $Stream->ReadLine()))
    {
        $Line =~ s/[\r\n]+$//so;

        if ($Line =~ m/^Properties on '(.+)':$/o)
        {
            if ($Path && $PropName)
            {
                $Props{$Path}->{$PropName} = $PropValue;
                $PropName = undef
            }

            $Path = $1
        }
        elsif ($Line =~ m/^  (.+) : (.*)$/o)
        {
            $Props{$Path}->{$PropName} = $PropValue if $PropName;

            ($PropName, $PropValue) = ($1, $2)
        }
        else
        {
            $PropValue .= $Line
        }
    }

    $Props{$Path}->{$PropName} = $PropValue if $Path && $PropName;

    $Stream->Close();

    return \%Props
}

sub ReadRevProps
{
    my ($Self, $Revision, @Args) = @_;

    my $Stream = $Self->Run(qw(proplist --revprop --verbose -r),
        $Revision, @Args);

    $Stream->ReadLine() =~ m/^Unversioned properties on revision (\d+):/;

    defined $1 && $1 eq $Revision || die 'Invalid proplist output';

    my %Props;
    my $PropName;
    my $PropValue;
    my $Line;

    while (defined($Line = $Stream->ReadLine()))
    {
        $Line =~ s/[\r\n]+$//so;

        if ($Line =~ m/^  (.+) : (.*)$/o)
        {
            $Props{$PropName} = $PropValue if $PropName;

            ($PropName, $PropValue) = ($1, $2)
        }
        else
        {
            $PropValue .= $Line
        }
    }

    $Props{$PropName} = $PropValue if $PropName;

    $Stream->Close();

    return \%Props
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

sub ReadLog
{
    my ($Self, @LogParams) = @_;

    my $Stream = $Self->Run('log', '--verbose', @LogParams);

    my $Line;
    my $State = 'initial';

    my @Revisions;
    my $CurrentRevision;
    my ($Time, $NumberOfLogLines);

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
            $State = 'initial' if --$NumberOfLogLines == 0;
            $CurrentRevision->{LogMessage} .= $Line . "\n"
        }
        elsif ($State eq 'revision_header')
        {
            my %NewRev = (LogMessage => '', ChangedPaths => []);

            push @Revisions, ($CurrentRevision = \%NewRev);

            (@NewRev{qw(Number Author)}, $Time, $NumberOfLogLines) = $Line =~
                m/^r(\d+) \| (.+?) \| (.+?) \(.+?\) \| (\d+) lines?$/o or
                    LogParsingError($Stream, $CurrentRevision, $State, $Line);

            my ($Year, $Month, $Day, $Hour, $Min, $Sec) =
                $Time =~ m/^(....)-(..)-(..) (..):(..):(..)/o;

            ($Sec, $Min, $Hour, $Day, $Month, $Year) = gmtime(timelocal($Sec,
                $Min, $Hour, $Day, $Month - 1, $Year - 1900));

            $NewRev{Time} = sprintf('%4d-%02d-%02dT%02d:%02d:%02d.000000Z',
                $Year + 1900, $Month + 1, $Day, $Hour, $Min, $Sec);

            $State = $NumberOfLogLines > 0 ? 'changed_path_header' : 'initial'
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
                unless $Line =~ m/^-{70}/o;

            $State = 'revision_header'
        }
    }

    $Stream->Close();

    $_->{LogMessage} =~ s/[\r\n]+$//so for @Revisions;

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