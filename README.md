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

The primary configuration parameter is a one-to-one mapping of a
set of non-overlapping directories in one or more source
repositories onto a set of non-overlapping directories in the
target repository.

Below is an example of a very basic configuration file.  It defines
one source repository and the path for it in the target repository.

    # Turn the entire 'source_repo' into a single directory inside
    # the target repository.
    {
        SourceRepositories =>
        [
            {
                RepoName => 'source_repo',
                RootURL => 'https://svn.example.org/repos/source_repo',
                TargetPath => 'path/in/target/repo'
            }
        ]
    }

This example becomes somewhat more practical with addition of
another source repository:

    # Turn the entire 'source_repo' into a single directory inside
    # the target repository.
    {
        SourceRepositories =>
        [
            {
                RepoName => 'red_source_repo',
                RootURL => 'https://svn/repos/red_repo',
                TargetPath => 'colors/red'
            }
        ],
        [
            {
                RepoName => 'blue_source_repo',
                RootURL => 'https://svn/repos/blue_repo',
                TargetPath => 'colors/blue'
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
