svn_replay
==========

This tool was created for internal use and with a single purpose.
It wasn't meant to be reused, let alone open sourced.
Yet I keep coming back to it whenever I need to perform a "surgery"
that `svndumpfilter` wasn't designed to handle. And so the tool is
released into the wild in hope that someone finds it useful.

`svn_replay` works by reading changesets of one or more source
repositories and reproducing (replaying) the same changes in the
target repository. The most likely scenario is that the target
repository is created from scratch by running `svn_replay -i`, but
it is also possible to use an existing repository as the target
repository. A local working copy of the target repository is
maintained to prepare commits.

Physical access to the repositories is not required; the usual
access protocol (`https`, `svn+ssh`, etc.) will suffice (although
using the `file` protocol makes the replication process
significantly faster).

All source repositories can be edited normally during the
replication. The target repository can also be modified externally
provided that all changes happen outside the configured
destination directories.

When `svn_replay` is used to merge or cherry-pick changes from two
or more source repositories, changesets that come from different
source repositories are sorted by their commit dates and times.
The relative order of changesets coming from each particular
repository is preserved though.

How to Install
==============

No installation required: simply run `svn_replay.pl` from the root
directory. A symbolic link to the script can be created if needed.

The script has no CPAN dependencies; all modules that it uses are
either bundled or come standard with Perl.

How to Configure
================

The configuration file for `svn_replay` is a simple Perl script,
which must end with a HASH definition.

Below is an example of a very basic configuration file.  It sets
up replication of a single directory of one source repository to a
directory inside the target repository.

```perl
{
    SourceRepositories =>
    [
        {
            RepoName => 'source_repo',
            RootURL => 'https://svn.example.org/repos/source_repo',
            PathMapping =>
            [
                {
                    SourcePath => 'path/in/source/repo',
                    TargetPath => 'path/in/target/repo'
                }
            ]
        }
    ]
}
```

The only required parameter in the root configuration hash is
`SourceRepositories`. The value of this key is an array of hashes,
each referring to a single source repository.

The example above uses only one source repository and therefore
its `SourceRepositories` array contains only one hash. The keys of
that hash are as follows:

- `RepoName` defines the name of the source repository.  This name
  is used internally and also appears in the output of the script.
  Note that because there is only one target repository, it does
  not need a name.

- `RootURL` defines the URL that will be used for repository
  access.

- `PathMapping` is the primary configuration parameter and defines
  a one-to-one mapping of a set of non-overlapping directories in
  the source repository onto a set of non-overlapping directories
  in the target repository.

In the example below, trunks of two source repositories become
sibling directories in the target repository:

```perl
{
    SourceRepositories =>
    [
        {
            RepoName => 'red_source_repo',
            RootURL => 'https://svn/repos/red_repo',
            PathMapping =>
            [
                {
                    SourcePath => 'trunk',
                    TargetPath => 'trunk/colors/red'
                }
            ]
        }
    ],
    [
        {
            RepoName => 'blue_source_repo',
            RootURL => 'https://svn/repos/blue_repo',
            PathMapping =>
            [
                {
                    SourcePath => 'trunk',
                    TargetPath => 'trunk/colors/blue'
                }
            ]
        }
    ]
}
```

Just like there can be multiple source repositories, there can be
multiple `PathMapping` elements for each repository.  Here's an
example where pathnames of the `include` and `src` directories of
a C library are rewritten so that the library has its own private
directory.

```perl
{
    SourceRepositories =>
    [
        {
            RepoName => 'source_repo',
            RootURL => 'https://svn.example.org/repos/source_repo',
            PathMapping =>
            [
                {
                    SourcePath => 'trunk/include/mylib',
                    TargetPath => 'trunk/mylib/include/mylib'
                },
                {
                    SourcePath => 'trunk/src/mylib',
                    TargetPath => 'trunk/mylib/src'
                }
            ]
        }
    ]
}
```

Optional Parameters
-------------------

Besides the three required keys (`RepoName`, `RootURL`, and
`PathMapping`), the hash that describes a single source repository
can also contain the following optional ones:

- `StopAtRevision` makes the replication process stop at a certain
  revision number in the source repository as opposed to HEAD. The
  commit history will be read up to and including the specified
  revision.

- `DiscardSvnExternals` prescribes that the `svn:externals`
  property must not be copied over to the target repository.
  By default, the `svn:externals` property is copied verbatim.

- `PreCommitHook` is a Perl subroutine that is called right before
  the target repository modifications are committed. The commit is
  aborted if this subroutine returns zero, in which case it's the
  responsibility of the pre-commit subroutine to clean up the
  working copy (revert all changes made by `svn_replay`).

The root hash can also contain the `CommitCredentials` key if the
target repository requires authentication. The value of this key
must be either a two-element array, in which case it's interpreted
as a username-password pair, or a scalar, if only the username is
needed.

For the most complete example of a configuration file, see the
bundled `svn_replay.example.conf`.

How to Run
==========

The script has two modes of operation, each described in its own
chapter below.

Target Repository Initialization
--------------------------------

    svn_replay.pl -i <TARGET_REPO_PATH> <CONF_FILE> <TARGET_WORKING_COPY>

When given the `-i` option, `svn_replay` creates and initializes
an empty target repository. In this mode, the configuration file
and the source repositories are only used to set modification date
for revision zero, which is chosen as the oldest modification date
among revision zero of all source repositories.

After the target repository has been created, it's checked out
into the specified working copy directory, which must not exist.

Incremental Replication
-----------------------

    svn_replay.pl <CONF_FILE> <TARGET_WORKING_COPY>

This is the normal mode of operation. When the `-i` option is not
specified, the script iterates over the source repositories to
check for new revisions. If any new changes have been made since
the last run in the configured source paths, those changes are
replicated in the target repository.

The script logs information about its progress to the standard
output. To save this log to a file, use shell redirection:

    svn_replay.pl my.conf workdir >> svn_replay.log
    # or: svn_replay.pl my.conf workdir | tee -a svn_replay.log

Limitations
===========

- `svn_replay` cannot clone the entire source repository unless
  all top-level directories of that repository are listed in the
  `PathMapping` configuration section.

- The employed path mapping scheme is not flexible enough to
  describe arbitrary repository restructuring (for example,
  merging into a single target directory). In some cases, however,
  the desired effect can be achieved by applying a chain of
  `svn_replay` transformations and/or using `PreCommitHook`.

Troubleshooting
===============

Anything doesn't look right?  Run `prove` while in the root
directory of the project (or run `t/test.pl` if `prove` is not
available).  File a bug.

Disclaimer
==========

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
OF PERFORMANCE, MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE,
TITLE AND NON-INFRINGEMENT.  IN NO EVENT SHALL ANYONE DISTRIBUTING
THE SOFTWARE BE LIABLE FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER
IN CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
