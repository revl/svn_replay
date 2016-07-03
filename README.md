svn_replay
==========

This tool was created for internal use and with a single purpose.
It wasn't meant to be reused, let alone open sourced.
Yet I keep coming back to it whenever I need to perform a surgery
that `svndumpfilter` wasn't designed to handle. So I thought I'd
share it here.

The primary configuration parameter of `svn_replay` is a
one-to-one mapping of a set of non-overlapping directories in one
or more source repositories onto a set of non-overlapping
directories in the target repository. The tool replicates the
changes from the source directories to the target directories.

If `svn_replay` is used to merge or cherry-pick changes from two
or more source repositories, the revisions of source repositories
are sorted by their commit times prior to applying them to the
target repository, so that the changes in the target repository
are consistent.

All source repositories can be edited normally during the
replication. The target repository can also be modified provided
that all changes happen outside the `svn_replay` destination
directories.

TBC

Disclamer
---------

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
    EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
    OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, TITLE AND
    NON-INFRINGEMENT.  IN NO EVENT SHALL ANYONE DISTRIBUTING THE
    SOFTWARE BE LIABLE FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN
    CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
    WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
