#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More tests => 7;

use File::Basename;
use File::Spec;

my @LibDirs;

BEGIN
{
    my $TestDir = File::Spec->rel2abs(dirname($0));

    push @LibDirs, File::Spec->catdir($TestDir, 'lib'),
        File::Spec->catdir(dirname($TestDir), 'lib')
}

use lib @LibDirs;

use NCBI::SVN::Replay::Conf;
use NCBI::SVN::Replay::Init;

use File::Temp;

my $RootURL = 'https://svn.example.org/repos/source_repo';

my $TestDate = '2000-01-01T00:00:00.000000Z';

{
    package MockSVN;

    sub new
    {
        return bless {}, $_[0]
    }

    sub ReadRevProps
    {
        my ($Self, $Revision, @URL) = @_;

        $Self->{RevisionArg} = $Revision;
        $Self->{URLArg} = $URL[0];

        return {'svn:date' => $TestDate}
    }

    sub RunOrDie
    {
        my ($Self, @CommandAndParams) = @_;

        $Self->{AdminCommandArg} = shift @CommandAndParams;
        return if $Self->{AdminCommandArg} ne 'svnadmin';

        $Self->{SubcommandArg} = shift @CommandAndParams;
        return if $Self->{SubcommandArg} ne 'create';

        $Self->{TargetRepoPathArg} = shift @CommandAndParams;
        mkdir $Self->{TargetRepoPathArg};
        mkdir $Self->{TargetRepoPathArg} . '/hooks';
    }

    sub RunSubversion
    {
        my ($Self, @Params) = @_;

        push @{$Self->{SubversionArgs}}, \@Params
    }
}

my $SVN = MockSVN->new();

my $Init = NCBI::SVN::Replay::Init->new(MyName => basename($0), SVN => $SVN);

my $Conf = NCBI::SVN::Replay::Conf->new(
    {
        SourceRepositories =>
        [
            {
                RepoName => 'source_repo',
                RootURL => $RootURL,
                PathMapping =>
                [
                    {
                        SourcePath => 'from/path',
                        TargetPath => 'to/path'
                    }
                ]
            }
        ]
    });

my $TargetWorkingCopy = 'path/to/working/copy';

my $TempDirObj = File::Temp->newdir();

my $TargetRepoPath = $TempDirObj->dirname();

# Make sure Init checks for whether the target repository
# already exists.
eval {$Init->Run($Conf, $TargetWorkingCopy, $TargetRepoPath)};
like($@, qr(already exists), 'Must not overwrite existing repos');

# Now delete the directory so that Init can create it.
rmdir $TargetRepoPath;
$Init->Run($Conf, $TargetWorkingCopy, $TargetRepoPath);

# Check that all method arguments supplied to the mock svn object
# contained expected values.

# ReadRevProps
is($SVN->{RevisionArg}, 0, 'Init must inquire only about revision 0');
is($SVN->{URLArg}, $RootURL, 'RootURL must match the configured one');

# RunOrDie
is($SVN->{AdminCommandArg}, 'svnadmin', 'Expect svnadmin command');
is($SVN->{SubcommandArg}, 'create', 'Expect svnadmin create');
is($SVN->{TargetRepoPathArg}, $TargetRepoPath, 'Expect target repo path');

# RunSubversion
my $TargetRepoURL = 'file://' . $TargetRepoPath;
is_deeply($SVN->{SubversionArgs},
    [
        [qw(propset --revprop -r0 svn:date), $TestDate, $TargetRepoURL],
        ['checkout', $TargetRepoURL, $TargetWorkingCopy]
    ]);

# vim: filetype=perl tabstop=4 shiftwidth=4 softtabstop=4 expandtab
