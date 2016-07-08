svn_replay
==========

This tool was created for internal use and with a single purpose.
It wasn't meant to be reused, let alone open sourced.
Yet I keep coming back to it whenever I need to perform a "surgery"
that `svndumpfilter` wasn't designed to handle. And so the tool is
published here in hope that someone else finds it useful.

`svn_replay` works by reading changesets of one or more source
repositories and reproducing (replaying) the same changes in the
target repository. The most likely scenario is that the target
repository is created by `svn_replay`, but it is also possible to
use an existing repository as the target repository for `svn_replay`.

The tool doesn't need physical access to the repositories; the
usual access protocol (`https`, `svn+ssh`, etc.) will suffice
(although using the `file` protocol makes the replication process
significantly faster).

All source repositories can be edited normally during the
replication. The target repository can also be modified externally
provided that all changes happen outside the `svn_replay`
destination directories.

When `svn_replay` is used to merge or cherry-pick changes from two
or more source repositories, the changesets of those repositories
will be interleaved in the target repository if their commit times
overlap. The result is a consistent and natural revision log.

Installation
------------

No installation required. Simply run `svn_replay.pl` from the root
directory. A symbolic link to the script can be created if needed.

Configuration
-------------

The primary configuration parameter of `svn_replay` is a
one-to-one mapping of a set of non-overlapping directories in one
or more source repositories onto a set of non-overlapping
directories in the target repository.

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
