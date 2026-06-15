using System.Runtime.InteropServices;
using Baballonia.LibV4L2Capture.V4L2;
using Microsoft.Extensions.Logging;
using OpenCvSharp;
using Capture = Baballonia.SDK.Capture;

namespace Baballonia.LibV4L2Capture;

public sealed class LibV4L2Capture(string source, ILogger<LibV4L2Capture> logger) : Capture(source, logger)
{
    private Device? _device;
    private CancellationTokenSource? _cts;
    private Task? _captureTask;

    public override Task<bool> StartCapture()
    {
        Device.DebugLog = msg => Logger.LogDebug("[V4L2] " + msg);
        try
        {
            _device = Device.Connect(Source);

            if (_device == null)
                return Task.FromResult(false);

            Logger.LogInformation($"Using pixel format: {_device.PixelFormat}");

            _device.StartCapture();
            IsReady = true;
        }
        catch (Exception e)
        {
            Logger.LogError(e.ToString());
            return Task.FromResult(false);
        }

        Logger.LogInformation("Capture setup complete, starting frame loop");
        _cts = new CancellationTokenSource();
        var token = _cts.Token;

        _captureTask = Task.Run(() => VideoCapture_UpdateLoop(token), token);

        return Task.FromResult(true);
    }

    private void DecodeMJPEG(byte[] frame)
    {
        var mat = Cv2.ImDecode(frame, ImreadModes.Grayscale);
        if (mat.Empty())
        {
            Logger.LogWarning($"ImDecode returned empty mat (frame was {frame.Length} bytes) — skipping");
            return;
        }
        SetRawMat(mat);
    }

    private void DecodeYUYV(byte[] frame, uint width, uint height)
    {
        var yuyvMat = new Mat((int)height, (int)width, MatType.CV_8UC2);
        Marshal.Copy(frame, 0, yuyvMat.Data, frame.Length);

        var grayMat = new Mat();
        Cv2.CvtColor(yuyvMat, grayMat, ColorConversionCodes.YUV2GRAY_YUY2);
        SetRawMat(grayMat);
    }

    private async Task VideoCapture_UpdateLoop(CancellationToken ct)
    {
        int frameCount = 0;
        int noFrameCount = 0;

        while (!ct.IsCancellationRequested && _device != null)
        {
            try
            {
                // FrameReady blocks up to 50ms waiting for POLLIN — reliable at any frame rate.
                // CaptureFrame internally calls FrameReady(50), so this loop idles at 20 Hz
                // when no frames arrive, while still responding to cancellation promptly.
                if (_device.CaptureFrame(out byte[]? frame))
                {
                    frameCount++;
                    noFrameCount = 0;

                    if (frameCount == 1 || frameCount % 100 == 0)
                        Logger.LogDebug($"Frame #{frameCount}: {frame?.Length ?? 0} bytes");

                    if (frame is { Length: > 0 })
                    {
                        switch (_device.PixelFormat)
                        {
                            case v4l2_pix_fmt.V4L2_PIX_FMT_MJPEG:
                                DecodeMJPEG(frame);
                                break;
                            case v4l2_pix_fmt.V4L2_PIX_FMT_YUYV:
                                var pix = _device.CurrentFormat.pix;
                                DecodeYUYV(frame, pix.width, pix.height);
                                break;
                            default:
                                throw new ArgumentOutOfRangeException();
                        }
                    }
                }
                else
                {
                    noFrameCount++;
                    if (noFrameCount % 20 == 0)
                        Logger.LogWarning($"No frame from device after {noFrameCount} polls (~{noFrameCount}s)");

                    // Yield to the async runtime briefly so cancellation is checked.
                    await Task.Yield();
                }
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch(Exception e)
            {
                SetRawMat(new Mat());
                IsReady = false;
                Logger.LogError(e.ToString());
                _device.Dispose();
                break;
            }
        }

        Logger.LogInformation($"Capture loop exited: {frameCount} frames captured");
    }

    public override Task<bool> StopCapture()
    {
        if (_device is null)
            return Task.FromResult(false);

        if (_captureTask != null)
        {
            _cts?.Cancel();
            _captureTask.Wait();
        }

        IsReady = false;
        _device?.Dispose();
        _device = null;
        return Task.FromResult(true);
    }
}
