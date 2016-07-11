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

Installation
------------

No installation required: simply run `svn_replay.pl` from the root
directory. A symbolic link to the script can be created if needed.

Configuration
-------------

The configuration file for `svn_replay` is a simple Perl script,
which must end with a HASH definition.

Below is an example of a very basic configuration file.  It sets
up replication of a single directory of one source repository to a
directory inside the target repository.

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

As can be seen from the example, the root configuration hash
consists of a single key, `SourceRepositories`, and the value of
this key is an array of hashes, each referring to a single source
repository.

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

Just like there can be multiple source repositories, there can be
multiple `PathMapping` elements for each repository.

In the example below, trunks of two source repositories become
sibling directories in the target repository:

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

And here's an example of multiple `PathMapping` elements defined
for one source repository:

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

TBC

Disclaimer
----------

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
OF PERFORMANCE, MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE,
TITLE AND NON-INFRINGEMENT.  IN NO EVENT SHALL ANYONE DISTRIBUTING
THE SOFTWARE BE LIABLE FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER
IN CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
