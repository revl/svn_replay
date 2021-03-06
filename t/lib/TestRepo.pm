use strict;
use warnings;

package TestRepo;

use base qw(NCBI::SVN::Base);

use File::Temp qw(tempdir);

sub new
{
    my $Class = shift;

    my $Self = $Class->SUPER::new(@_);

    my $ParentDir = $Self->{ParentDir};

    die if not defined $ParentDir;

    my $RepoPath = $Self->{RepoPath} =
        tempdir('source_repo_XXXXXX', DIR => $ParentDir);

    my $SVN = $Self->{SVN};

    $SVN->RunOrDie(qw(svnadmin create), $RepoPath);

    my $Hook = "$RepoPath/hooks/pre-revprop-change";
    open my $File, '>', $Hook or die;
    print $File "#!/bin/sh\nexit 0\n" or die;
    close $File;
    chmod 0755, $Hook or die;

    my $RepoURL = $Self->{RepoURL} = 'file://' . $RepoPath;

    my $WorkingCopyPath = $Self->{WorkingCopyPath} =
        File::Temp::tempnam($ParentDir, 'source_wd_XXXXXX');

    $SVN->RunSubversion('checkout', $RepoURL, $WorkingCopyPath);

    return $Self
}

sub CreateMissingDirs
{
    my ($Self, $FilePath) = @_;

    my $SVN = $Self->{SVN};

    my $DirPath = $Self->{WorkingCopyPath};

    my @Subdirs = split('/', $FilePath);
    pop @Subdirs;

    while (@Subdirs)
    {
        $DirPath .= '/' . shift @Subdirs;

        unless (-e $DirPath)
        {
            $SVN->RunSubversion('mkdir', $DirPath);

            while (@Subdirs)
            {
                $DirPath .= '/' . shift @Subdirs;
                $SVN->RunSubversion('mkdir', $DirPath)
            }

            last
        }
    }
}

sub Put
{
    my ($Self, $FilePath, $FileContents) = @_;

    $Self->CreateMissingDirs($FilePath);

    $FilePath = $Self->{WorkingCopyPath} . '/' . $FilePath;

    my $FileExisted = -e $FilePath;

    open my $File, '>', $FilePath or die "$FilePath\: $!";
    print $File $FileContents;
    close $File;

    $Self->{SVN}->RunSubversion('add', $FilePath) unless $FileExisted;

    return $FilePath
}

sub Delete
{
    my ($Self, $FilePath) = @_;

    $FilePath = $Self->{WorkingCopyPath} . '/' . $FilePath;

    $Self->{SVN}->RunSubversion('delete', $FilePath) if -e $FilePath;

    return $FilePath
}

sub Copy
{
    my ($Self, $FromPath, $ToPath) = @_;

    $Self->CreateMissingDirs($ToPath);

    $FromPath = $Self->{WorkingCopyPath} . '/' . $FromPath;
    $ToPath = $Self->Delete($ToPath);

    $Self->{SVN}->RunSubversion('copy', $FromPath, $ToPath);

    return $ToPath
}

sub Move
{
    my ($Self, $FromPath, $ToPath) = @_;

    $Self->CreateMissingDirs($ToPath);

    $FromPath = $Self->{WorkingCopyPath} . '/' . $FromPath;
    $ToPath = $Self->Delete($ToPath);

    $Self->{SVN}->RunSubversion('move', $FromPath, $ToPath);

    return $ToPath
}

sub Commit
{
    my ($Self, $Message) = @_;

    my $Stream = $Self->{SVN}->Run('commit', '-m', $Message,
        $Self->{WorkingCopyPath});

    my $Line;
    my $Revision;

    while (defined($Line = $Stream->ReadLine()))
    {
        print "$Line\n";
        ($Revision) = $Line =~ m/revision (\d+)/so
    }

    $Self->{SVN}->RunSubversion('update', $Self->{WorkingCopyPath});

    return $Revision
}

1

# vim: filetype=perl tabstop=4 shiftwidth=4 softtabstop=4 expandtab
