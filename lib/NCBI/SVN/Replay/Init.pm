package NCBI::SVN::Replay::Init;

use strict;
use warnings;

use base qw(NCBI::SVN::Base);

use NCBI::SVN::Replay::Conf;

sub Run
{
    my ($Self, $ConfFile, $TargetWorkingCopy, $InitPath) = @_;

    if (-d $InitPath)
    {
        die "$Self->{MyName}: cannot create repository: " .
            "$InitPath already exists.\n"
    }

    my $Conf = NCBI::SVN::Replay::Conf->new($ConfFile);

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
