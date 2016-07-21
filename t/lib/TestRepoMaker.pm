use strict;
use warnings;

package TestRepoMaker;

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

    $Self->{SVN}->RunSubversion('commit', '-m', $Message, $Self->{CheckoutPath})
}

1

# vim: filetype=perl tabstop=4 shiftwidth=4 softtabstop=4 expandtab
