import fuse.fuse;
import std.conv;
import std.stdio;
import std.string;
import core.sys.posix.fcntl;
import std.stdio;
import std.exception;

enum O_RDONLY=0;
class HelloFs : DefaultFileSystem {
	override int getattr (in char* c_path, stat_t* stbuf) {
    string path = to!string(c_path);
		if(path=="/") {
			stbuf.st_mode = S_IFDIR | octal!755;
			stbuf.st_nlink = 2;
      return 0;
		}
		else if(path==hello_path) {
			stbuf.st_mode = S_IFREG | octal!444;
			stbuf.st_nlink = 1;
			stbuf.st_size = hello_str.length;
      return 0;
		}
    return -ENOENT;
	}
	override int readdir (in char* c_path, void* buf, fuse_fill_dir_t filler, off_t offset, fuse_file_info *info) {
    string path = to!string(c_path);
		if(path!="/") {
      return -ENOENT;
		}
		
		filler(buf, ".", null, 0);
		filler(buf, "..", null, 0);
		filler(buf, hello_path.ptr+1, null, 0);
    return 0;
	}
	override int open (in char* c_path, fuse_file_info *info) {
    string path = to!string(c_path);
		if(path!=hello_path) {
      return -ENOENT;
		}

		if((info.flags & 3) != O_RDONLY) {
			return -EACCES;
		}
    return 0;
	}
	override int read (in char* c_path, ubyte* readbuf, size_t size, off_t offset, fuse_file_info* info) {
    writefln(format("size: %d, offset: %d", cast(uint)size, cast(uint)offset));
    string path = to!string(c_path);
		if(path!=hello_path) {
			return -ENOENT;
		}
		size_t len = hello_str.length-cast(size_t)offset; // Cast save, hello world will never be larger than 2GB.
		len = size > len ? len : size;
		if(offset<hello_str.length && offset>=0) {
			readbuf[0..len] = cast(immutable(ubyte)[])hello_str[cast(size_t)offset..len];
			return cast(int)(len);
		}
		else
			return 0;
	}

  override int opendir(in char* c_path, fuse_file_info* info) {
    return 0;
  }

  override int fgetattr(in char* c_path, stat_t* stbuf, fuse_file_info* info) {
    return 0;
  }
	private:
	static string hello_path="/hello";
	static string hello_str="Hello World!\n";
}

void main(string[] args) {
	auto myfs=new HelloFs();
	fuse_main(args, myfs);
}
