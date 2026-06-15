using Baballonia.SDK;
using Microsoft.Extensions.Logging;

namespace Baballonia.OpenCVCapture;

public class OpenCvCaptureFactory(ILoggerFactory loggerFactory) : ICaptureFactory
{
    public Capture Create(string address)
    {
        return new OpenCvCapture(address, loggerFactory.CreateLogger<OpenCvCapture>());
    }

    public bool CanConnect(string address)
    {
        var lowered = address.ToLower();
        var serial = lowered.StartsWith("com") ||
                     lowered.StartsWith("/dev/tty") ||
                     lowered.StartsWith("/dev/cu") ||
                     lowered.StartsWith("/dev/ttyacm");;
        if (serial) return false;

        // On Linux, /dev/video* devices go to LibV4L2Capture which handles MJPEG natively.
        // OpenCvCapture's GStreamer backend can't negotiate MJPEG-only V4L2 devices.
        if (OperatingSystem.IsLinux() && lowered.StartsWith("/dev/video")) return false;

        return lowered.StartsWith("/dev/video") ||
               lowered.EndsWith("appsink") ||
               address == "HTC Multimedia Camera" ||
               int.TryParse(address, out _) ||
               Uri.TryCreate(address, UriKind.Absolute, out _);
    }

    public string GetProviderName() => "Normal Camera";
}
