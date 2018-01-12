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

package NCBI::SVN::Wrapper::Stream;

use strict;
use warnings;

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

1

# vim: filetype=perl tabstop=4 shiftwidth=4 softtabstop=4 expandtab
