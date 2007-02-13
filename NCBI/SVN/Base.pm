package NCBI::SVN::Base;

use strict;
use warnings;
use Carp qw(confess);

use File::Spec;

sub FindSubversion
{
    for my $Path (File::Spec->path())
    {
        for my $Program qw(svn svn.bat svn.exe)
        {
            my $Pathname = File::Spec->catfile($Path, $Program);

            return $Pathname if -x $Pathname
        }
    }

    confess 'Unable to find "svn" in PATH'
}

sub new
{
    my ($Class, %Param) = @_;

    return bless
    {
        MyName => ($Param{MyName} || __PACKAGE__),
        SvnPath => ($Param{SvnPath} || FindSubversion())
    }, $Class
}

sub GetSvnPath
{
    my ($Self) = @_;

    return $Self->{SvnPath}
}

sub CallSubversion
{
    my ($Self, @Params) = @_;

    local $" = '" "';

    my @Output = `"$Self->{SvnPath}" "@Params"`;
    chomp @Output;

    return @Output
}

1
