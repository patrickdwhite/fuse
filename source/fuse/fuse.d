module fuse.fuse;
//import fuse.util;
import std.traits;
import std.string;
import std.algorithm;
import std.bitmanip;
import std.array;
import core.stdc.config;
import core.sys.posix.sys.types;
public import core.sys.posix.sys.statvfs;
public import core.stdc.errno;
public import core.sys.posix.sys.stat : stat_t; 
public import core.sys.posix.time;
import core.sys.posix.fcntl; 
import core.sys.posix.utime;
import std.container;

static string cleanParamsAsString(T, string fname)() {
  alias ParameterTypeTuple!(__traits(getMember, T, fname)) params;
  string result;
  static if (fname == "read") {
    result ~= "(in char*, ubyte*, ulong, long, fuse_file_info*)";
  } else static if (fname == "readdir") {
    result ~= "(in char*, void *, fuse_fill_dir_t, off_t, fuse_file_info *)";
  } else {
    result ~= params.stringof;
  }
  return result.replace("const(char[])", "const(char*)");
}

const shim_prefix = "shim_fuse_to_";

static string createFuseShim(T, string fname)() {
  alias ReturnType!(__traits(getMember, T, fname)) ret_type;
  alias ParameterTypeTuple!(__traits(getMember, T, fname)) params;
  string result = format("extern (C) %s %s%s", ret_type.stringof, shim_prefix, fname);
  result ~= cleanParamsAsString!(T, fname) ~ " { ";
  result ~= "auto context=fuse_get_context();\n";
  result ~= "auto ops=cast(DefaultFileSystem)context.private_data;\n";
  result ~= format("return ops.%s", fname);
  result ~= "(";
  foreach(i, n; params) {
    result ~= format("_param_%d", i);
    if (i != params.length - 1) result ~= ", ";
  }
  result ~= "); }";
  return result;
}

static string createShimStruct(T, string sname)() {
  string result = format("fuse_operations %s = {\n", sname);
  foreach(m; __traits(allMembers, T)) {
    static if (!m.startsWith("flag") && !m.startsWith("_") ){
      result ~= format("%s: &%s%s,\n", m, shim_prefix, m);
    }
  }
  return result ~ "};\n";
}

static string createShimsFromStruct(T)() {
  string result;
  foreach(m; __traits(allMembers, T)) {
    static if (!m.startsWith("flag") && !m.startsWith("_") ){
      result ~= createFuseShim!(T, m);
    }
    result ~= "\n";
  }
  return result;
}

static string createDefaultImpl(T)() {
  string result;
  foreach(m; __traits(allMembers, T)) {
    static if (!m.startsWith("flag") && !m.startsWith("_") ){
      alias ReturnType!(__traits(getMember, T, m)) ret_type;
      result ~= ret_type.stringof ~ " ";
      result ~= m ~ " " ~ cleanParamsAsString!(T, m);
      static if (__traits(isArithmetic, ret_type)) {
        result ~= " { return -ENOSYS; }";
      } else static if (m == "init") { 
        result ~= " { return cast(void*)this; }";
      } else {
        result ~= " { }";
      }
    }
    result ~= "\n";
  }
  return result;
}

mixin(createShimsFromStruct!fuse_operations);

class DefaultFileSystem {
  mixin(createDefaultImpl!fuse_operations);
	bool isNullPathOk() @property { return false; }
}

int fuse_main(const(char[])[] args, DefaultFileSystem operations) {
	const(char)*[] c_args=new const(char)*[](args.length);
	foreach(i, arg; args) 
		c_args[i]=arg.ptr;
  mixin(createShimStruct!(fuse_operations, "fuseops"));
  fuseops.flag_nullpath_ok = operations.isNullPathOk;
  return fuse_main_real(cast(int)c_args.length, c_args.ptr, &fuseops, fuseops.sizeof, cast(void*)operations);
}

extern(C):
alias int function (void* buf, in char*  name, const stat_t* stbuf, off_t offset) fuse_fill_dir_t;	
extern struct fuse_dirhandle;
extern struct fuse_pollhandle;

int fuse_notify_poll(fuse_pollhandle *ph);
//alias fuse_fill_dir_t* fuse_dirhandle;

struct fuse_file_info {
	/** Open flags.	 Available in open() and release() */
	int flags;

	/** Old file handle, don't use */
	c_ulong fh_old;


	/** In case of a write operation indicates if this was caused by a
	  writepage */
	int writepage;
	mixin(bitfields!(
		bool, "direct_io", 1,
		bool, "keep_cache", 1,
		bool, "flush", 1,
		bool, "unseekable", 1,
		uint, "padding", 28));

	/** File handle.  May be filled in by filesystem in open().
	  Available in all other file operations */
	ulong fh;

	/** Lock owner id.  Available in locking operations and flush */
	ulong lock_owner;
};
version(unittest) {
extern size_t c_get_fuse_file_info_size();
// Expectes the bitfield to be set this way:
// direct_io:1, keep_cache:0, flushe:1, nonseekable:0
extern int bit_field_check_fuse_file_info(fuse_file_info* test); 
}
unittest {
	assert(fuse_file_info.sizeof==c_get_fuse_file_info_size());
	fuse_file_info my_info;
	with(my_info) {
		direct_io=1;
		keep_cache=0;
		flush=1;
		unseekable=0;
	}
	assert(bit_field_check_fuse_file_info(&my_info));
}

package:

alias void* fuse_dirfil_t; // Not correct, but it is deprecated anyway.
alias void* fuse_dirh_t; // Not correct but deprecated anyway.
// Forward declarations:
extern struct struct_fuse; // Renamed to avoid name clashes.
// Main entry point:
extern int fuse_main_real(int argc, const(char)** argv, const fuse_operations *op,
	   size_t op_size, void *user_data);

extern fuse_context *fuse_get_context();

struct fuse_operations {
	/** Get file attributes.
	 *
	 * Similar to stat().  The 'st_dev' and 'st_blksize' fields are
	 * ignored.	 The 'st_ino' field is ignored except if the 'use_ino'
	 * mount option is given.
	 */
	int function (in char* , stat_t*) getattr;

	/** Read the target of a symbolic link
	 *
	 * The buffer should be filled with a null terminated string.  The
	 * buffer size argument includes the space for the terminating
	 * null character.	If the linkname is too long to fit in the
	 * buffer, it should be truncated.	The return value should be 0
	 * for success.
	 */
	int function (in char* , ubyte *, size_t) readlink;

	/* Deprecated, use readdir() instead */
	int function (in char* , fuse_dirh_t, fuse_dirfil_t) getdir;

	/** Create a file node
	 *
	 * This is called for creation of all non-directory, non-symlink
	 * nodes.  If the filesystem defines a create() method, then for
	 * regular files that will be called instead.
	 */
	int function (in char* , mode_t, dev_t) mknod;

	/** Create a directory 
	 *
	 * Note that the mode argument may not have the type specification
	 * bits set, i.e. S_ISDIR(mode) can be false.  To obtain the
	 * correct directory type bits use  mode|S_IFDIR
	 * */
	int function (in char* , mode_t) mkdir;

	/** Remove a file */
	int function (in char* ) unlink;

	/** Remove a directory */
	int function (in char* ) rmdir;

	/** Create a symbolic link */
	int function (in char* , in char* ) symlink;

	/** Rename a file */
	int function (in char* , in char* ) rename;

	/** Create a hard link to a file */
	int function (in char* , in char* ) link;


	/** Change the permission bits of a file */
	int function (in char* , mode_t) chmod;

	/** Change the owner and group of a file */
	int function (in char* , uid_t, gid_t) chown;

	/** Change the size of a file */
	int function (in char* , off_t) truncate;

  /** Change the access and/or modification times of a file
   *
   * Deprecated, use utimens() instead.
   */
	int function (in char* , utimbuf *) utime;

	/** File open operation
	 *
	 * No creation (O_CREAT, O_EXCL) and by default also no
	 * truncation (O_TRUNC) flags will be passed to open(). If an
	 * application specifies O_TRUNC, fuse first calls truncate()
	 * and then open(). Only if 'atomic_o_trunc' has been
	 * specified and kernel version is 2.6.24 or later, O_TRUNC is
	 * passed on to open.
	 *
	 * Unless the 'default_permissions' mount option is given,
	 * open should check if the operation is permitted for the
	 * given flags. Optionally open may also return an arbitrary
	 * filehandle in the fuse_file_info structure, which will be
	 * passed to all file operations.
	 *
	 * Changed in version 2.2
	 */
	int function (in char* , fuse_file_info *) open;

	/** Read data from an open file
	 *
	 * Read should return exactly the number of bytes requested except
	 * on EOF or error, otherwise the rest of the data will be
	 * substituted with zeroes.	 An exception to this is when the
	 * 'direct_io' mount option is specified, in which case the return
	 * value of the read system call will reflect the return value of
	 * this operation.
	 *
	 * Changed in version 2.2
	 */
	int function (in char* , ubyte *, size_t, off_t,
			fuse_file_info *) read;

	/** Write data to an open file
	 *
	 * Write should return exactly the number of bytes requested
	 * except on error.	 An exception to this is when the 'direct_io'
	 * mount option is specified (see read operation).
	 *
	 * Changed in version 2.2
	 */
	int function (in char* , in ubyte* , size_t, off_t,
			fuse_file_info *) write;

	/** Get file system statistics
	 *
	 * The 'f_frsize', 'f_favail', 'f_fsid' and 'f_flag' fields are ignored
	 *
	 * Replaced 'struct statfs' parameter with 'struct statvfs' in
	 * version 2.5
	 */
	int function (in char* , statvfs_t *) statfs;

	/** Possibly flush cached data
	 *
	 * BIG NOTE: This is not equivalent to fsync().  It's not a
	 * request to sync dirty data.
	 *
	 * Flush is called on each close() of a file descriptor.  So if a
	 * filesystem wants to return write errors in close() and the file
	 * has cached dirty data, this is a good place to write back data
	 * and return any errors.  Since many applications ignore close()
	 * errors this is not always useful.
	 *
	 * NOTE: The flush() method may be called more than once for each
	 * open().	This happens if more than one file descriptor refers
	 * to an opened file due to dup(), dup2() or fork() calls.	It is
	 * not possible to determine if a flush is final, so each flush
	 * should be treated equally.  Multiple write-flush sequences are
	 * relatively rare, so this shouldn't be a problem.
	 *
	 * Filesystems shouldn't assume that flush will always be called
	 * after some writes, or that if will be called at all.
	 *
	 * Changed in version 2.2
	 */
	int function (in char* , fuse_file_info *) flush;

	/** Release an open file
	 *
	 * Release is called when there are no more references to an open
	 * file: all file descriptors are closed and all memory mappings
	 * are unmapped.
	 *
	 * For every open() call there will be exactly one release() call
	 * with the same flags and file descriptor.	 It is possible to
	 * have a file opened more than once, in which case only the last
	 * release will mean, that no more reads/writes will happen on the
	 * file.  The return value of release is ignored.
	 *
	 * Changed in version 2.2
	 */
	int function (in char* , fuse_file_info *) release;

	/** Synchronize file contents
	 *
	 * If the datasync parameter is non-zero, then only the user data
	 * should be flushed, not the meta data.
	 *
	 * Changed in version 2.2
	 */
	int function (in char* , int, fuse_file_info *) fsync;

	/** Set extended attributes */
	int function (in char* , in char* , in ubyte* , size_t, int) setxattr;

	/** Get extended attributes */
	int function (in char* , in char* , ubyte *, size_t) getxattr;

	/** List extended attributes
	 * @param list Provide all attribute names separated by '\0'.
	 */
	int function (in char* , char *, size_t) listxattr;

	/** Remove extended attributes */
	int function (in char* , in char* ) removexattr;

	/** Open directory
	 *
	 * Unless the 'default_permissions' mount option is given,
	 * this method should check if opendir is permitted for this
	 * directory. Optionally opendir may also return an arbitrary
	 * filehandle in the fuse_file_info structure, which will be
	 * passed to readdir, closedir and fsyncdir.
	 *
	 * Introduced in version 2.3
	 */
	int function (in char* , fuse_file_info *) opendir;

	/** Read directory
	 *
	 * This supersedes the old getdir() interface.  New applications
	 * should use this.
	 *
	 * The filesystem may choose between two modes of operation:
	 *
	 * 1) The readdir implementation ignores the offset parameter, and
	 * passes zero to the filler function's offset.  The filler
	 * function will not return '1' (unless an error happens), so the
	 * whole directory is read in a single readdir operation.  This
	 * works just like the old getdir() method.
	 *
	 * 2) The readdir implementation keeps track of the offsets of the
	 * directory entries.  It uses the offset parameter and always
	 * passes non-zero offset to the filler function.  When the buffer
	 * is full (or an error happens) the filler function will return
	 * '1'.
	 *
	 * Introduced in version 2.3
	 */
	int function (in char* , void *, fuse_fill_dir_t, off_t,	fuse_file_info *) readdir;

	/** Release directory
	 *
	 * Introduced in version 2.3
	 */
	int function (in char* , fuse_file_info *) releasedir;

	/** Synchronize directory contents
	 *
	 * If the datasync parameter is non-zero, then only the user data
	 * should be flushed, not the meta data
	 *
	 * Introduced in version 2.3
	 */
	int function (in char* , int, fuse_file_info *) fsyncdir;

	/**
	 * Initialize filesystem.
	 *
	 * Introduced in version 2.3
	 * Changed in version 2.6
	 */
	void* function (fuse_conn_info *conn) init;

	/**
	 * Clean up filesystem
	 *
	 * Called on filesystem exit.
	 *
	 * Introduced in version 2.3
	 */
	void function (void* data) destroy;

	/**
	 * Check file access permissions
	 *
	 * This will be called for the access() system call.  If the
	 * 'default_permissions' mount option is given, this method is not
	 * called.
	 *
	 * This method is not called under Linux kernel versions 2.4.x
	 *
	 * Introduced in version 2.5
	 */
	int function (in char* , int) access;

	/**
	 * Create and open a file
	 *
	 * If the file does not exist, first create it with the specified
	 * mode, and then open it.
	 *
	 * If this method is not implemented or under Linux kernel
	 * versions earlier than 2.6.15, the mknod() and open() methods
	 * will be called instead.
	 *
	 * Introduced in version 2.5
	 */
	int function (in char* , mode_t, fuse_file_info *) create;

	/**
	 * Change the size of an open file
	 *
	 * This method is called instead of the truncate() method if the
	 * truncation was invoked from an ftruncate() system call.
	 *
	 * If this method is not implemented or under Linux kernel
	 * versions earlier than 2.6.15, the truncate() method will be
	 * called instead.
	 *
	 * Introduced in version 2.5
	 */
	int function (in char* , off_t, fuse_file_info *) ftruncate;

	/**
	 * Get attributes from an open file
	 *
	 * This method is called instead of the getattr() method if the
	 * file information is available.
	 *
	 * Currently this is only called after the create() method if that
	 * is implemented (see above).  Later it may be called for
	 * invocations of fstat() too.
	 *
	 * Introduced in version 2.5
	 */
	int function (in char* , stat_t *, fuse_file_info *) fgetattr;

	/**
	 * Perform POSIX file locking operation
	 *
	 * The cmd argument will be either F_GETLK, F_SETLK or F_SETLKW.
	 *
	 * For the meaning of fields in 'struct flock' see the man page
	 * for fcntl(2).  The l_whence field will always be set to
	 * SEEK_SET.
	 *
	 * For checking lock ownership, the 'fuse_file_info->owner'
	 * argument must be used.
	 *
	 * For F_GETLK operation, the library will first check currently
	 * held locks, and if a conflicting lock is found it will return
	 * information without calling this method.	 This ensures, that
	 * for local locks the l_pid field is correctly filled in.	The
	 * results may not be accurate in case of race conditions and in
	 * the presence of hard links, but it's unlikly that an
	 * application would rely on accurate GETLK results in these
	 * cases.  If a conflicting lock is not found, this method will be
	 * called, and the filesystem may fill out l_pid by a meaningful
	 * value, or it may leave this field zero.
	 *
	 * For F_SETLK and F_SETLKW the l_pid field will be set to the pid
	 * of the process performing the locking operation.
	 *
	 * Note: if this method is not implemented, the kernel will still
	 * allow file locking to work locally.  Hence it is only
	 * interesting for network filesystems and similar.
	 *
	 * Introduced in version 2.6
	 */
	int function (in char* , fuse_file_info *, int cmd,
			flock *) lock;

	/**
	 * Change the access and modification times of a file with
	 * nanosecond resolution
	 *
	 * Introduced in version 2.6
	 */
	int function (in char* , const timespec *tv) utimens;

	/**
	 * Map block index within file to block index within device
	 *
	 * Note: This makes sense only for block device backed filesystems
	 * mounted with the 'blkdev' option
	 *
	 * Introduced in version 2.6
	 */
	int function (in char* , size_t blocksize, ulong *idx) bmap;

	mixin(bitfields!(
		bool, "flag_nullpath_ok", 1,
		uint, "flag_reserved", 31));

	/**
	 * Ioctl
	 *
	 * flags will have FUSE_IOCTL_COMPAT set for 32bit ioctls in
	 * 64bit environment.  The size and direction of data is
	 * determined by _IOC_*() decoding of cmd.  For _IOC_NONE,
	 * data will be NULL, for _IOC_WRITE data is out area, for
	 * _IOC_READ in area and if both are set in/out area.  In all
	 * non-NULL cases, the area is of _IOC_SIZE(cmd) bytes.
	 *
	 * Introduced in version 2.8
	 */
	int function (in char* , int cmd, void *arg,	fuse_file_info *, uint flags, void *data) ioctl;

	/**
	 * Poll for IO readiness events
	 *
	 * Note: If ph is non-NULL, the client should notify
	 * when IO readiness events occur by calling
	 * fuse_notify_poll() with the specified ph.
	 *
	 * Regardless of the number of times poll with a non-NULL ph
	 * is received, single notification is enough to clear all.
	 * Notifying more times incurs overhead but doesn't harm
	 * correctness.
	 *
	 * The callee is responsible for destroying ph with
	 * fuse_pollhandle_destroy() when no longer in use.
	 *
	 * Introduced in version 2.8
	 */
	int function (in char* , fuse_file_info *, fuse_pollhandle *ph, uint *reventsp) poll;
}

/** Extra context that may be needed by some filesystems
 *
 * The uid, gid and pid fields are not filled in case of a writepage
 * operation.
 */
struct fuse_context {
	/** Pointer to the fuse object */
	struct_fuse *fuse;

	/** User ID of the calling process */
	uid_t uid;

	/** Group ID of the calling process */
	gid_t gid;

	/** Thread ID of the calling process */
	pid_t pid;

	/** Private filesystem data */
	void *private_data;

	/** Umask of the calling process (introduced in version 2.8) */
	mode_t umask;
};

struct AccessContext {
		private this(fuse_context* fc) {
			uid=fc.uid;
			gid=fc.gid;
			pid=fc.pid;
			umask=fc.umask;
		}
		uid_t uid;
		gid_t gid;
		pid_t pid;
		mode_t umask;
}
/**
 * Connection information, passed to the ->init() method
 *
 * Some of the elements are read-write, these can be changed to
 * indicate the value requested by the filesystem.  The requested
 * value must usually be smaller than the indicated value.
 */
struct fuse_conn_info {
	/**
	 * Major version of the protocol (read-only)
	 */
	private uint proto_major_;
	@property uint proto_major() {
		return proto_major_;
	}

	/**
	 * Minor version of the protocol (read-only)
	 */
	private uint proto_minor_;
	@property uint proto_minor() {
		return proto_minor;
	}

	/**
	 * Is asynchronous read supported (read-write)
	 */
	uint async_read;

	/**
	 * Maximum size of the write buffer
	 */
	uint max_write;

	/**
	 * Maximum readahead
	 */
	uint max_readahead;

	/**
	 * Capability flags, that the kernel supports
	 */
	uint capable;

	/**
	 * Capability flags, that the filesystem wants to enable
	 */
	uint want;

	/**
	 * For future use.
	 */
	uint[25] reserved;
}
