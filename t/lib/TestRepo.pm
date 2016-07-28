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
        tempdir('repoXXXXXX', DIR => $ParentDir);

    my $SVN = $Self->{SVN};

    $SVN->RunOrDie(qw(svnadmin create), $RepoPath);

    my $Hook = "$RepoPath/hooks/pre-revprop-change";
    open FILE, '>', $Hook or die;
    print FILE "#!/bin/sh\nexit 0\n" or die;
    close FILE;
    chmod 0755, $Hook or die;

    my $RepoURL = $Self->{RepoURL} = 'file://' . $RepoPath;

    my $CheckoutPath = $Self->{CheckoutPath} =
        File::Temp::tempnam($ParentDir, 'checkoutXXXXXX');

    $SVN->RunSubversion('checkout', $RepoURL, $CheckoutPath);

    return $Self
}

sub Put
{
    my ($Self, $FilePath, $FileContents) = @_;

    my $SVN = $Self->{SVN};

    my $DirPath = $Self->{CheckoutPath};

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

    $FilePath = $Self->{CheckoutPath} . '/' . $FilePath;

    my $FileExisted = -e $FilePath;

    open FILE, '>', $FilePath or die "$FilePath\: $!";
    print FILE $FileContents;
    close FILE;

    $Self->{SVN}->RunSubversion('add', $FilePath) unless $FileExisted;

    return $FilePath
}

sub Commit
{
    my ($Self, $Message) = @_;

    my $Stream = $Self->{SVN}->Run('commit', '-m', $Message,
        $Self->{CheckoutPath});

    my $Line;
    my $Revision;

    while (defined($Line = $Stream->ReadLine()))
    {
        print "$Line\n";
        ($Revision) = $Line =~ m/revision (\d+)/so
    }

    return $Revision
}

1

# vim: filetype=perl tabstop=4 shiftwidth=4 softtabstop=4 expandtab