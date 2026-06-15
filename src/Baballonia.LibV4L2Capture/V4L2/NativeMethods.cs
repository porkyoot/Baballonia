using System.Runtime.InteropServices;

namespace Baballonia.LibV4L2Capture.V4L2;

internal static class NativeMethods {
    // Use raw libc syscalls instead of libv4l2 wrappers. libv4l2 intercepts VIDIOC_S_FMT
    // on MJPEG-only devices to set up its own format conversion, which then causes our
    // subsequent VIDIOC_S_FMT calls to fail with EBUSY. Since we decode MJPEG ourselves
    // via Cv2.ImDecode, we don't need libv4l2's conversion layer.
    [DllImport("libc.so.6", SetLastError = true, EntryPoint = "open")]
    public static extern int v4l2_open([MarshalAs(UnmanagedType.LPStr)] string file, int flags);

    [DllImport("libc.so.6", SetLastError = true, EntryPoint = "close")]
    public static extern int v4l2_close(int fd);

    [DllImport("libc.so.6", SetLastError = true, EntryPoint = "ioctl")]
    public static extern int v4l2_ioctl(int fd, uint request, IntPtr arg);

    public static int v4l2_ioctl_safe<T>(int fd, uint request, ref T arg)
        where T : unmanaged
    {
        unsafe
        {
            fixed (T* p = &arg)
            {
                return v4l2_ioctl(fd, request, (IntPtr)p);
            }
        }
    }


    [DllImport("libc", SetLastError = true)]
    public static extern IntPtr mmap(
        IntPtr addr,
        uint length,
        Prot prot,
        MapFlags flags,
        int fd,
        IntPtr offset);

    [DllImport("libc", SetLastError = true)]
    public static extern int munmap(IntPtr addr, uint length);

    [DllImport("libc", SetLastError = true)]
    public static extern int poll([In, Out] Data.pollfd[] fds, uint nfds, int timeout);
}
