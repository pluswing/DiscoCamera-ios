//
//  ViewController.swift
//  DiscoCamra
//
//  Created by pluswing on 2018/09/09.
//  Copyright © 2018年 pluswing. All rights reserved.
//

import UIKit
import AVFoundation
import Photos

class ViewController: UIViewController {
    
    @IBOutlet weak var previewView: UIView!
    
    var videoDevice: AVCaptureDevice?
    var captureSession = AVCaptureSession()
    
    var width = 0
    var height = 0
    var writer: AVAssetWriter?
    
    var videoInput: AVAssetWriterInput?
    var videoInputAdapter: AVAssetWriterInputPixelBufferAdaptor?
    var audioInput: AVAssetWriterInput?
    
    var writing = false
    var offsetTime = kCMTimeZero
    
    var isRecording : Bool = false
    var timer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // 入力（背面カメラ）
        videoDevice = AVCaptureDevice.default(for: AVMediaType.video)
        let videoInput = try! AVCaptureDeviceInput.init(device: videoDevice!)
        captureSession.addInput(videoInput)
        
        //　ビデオサイズを取得。
        // ビデオはデフォルトLandscape。
        // 今回はportraitで撮るので、高さと幅を逆に持っておく。
        let dim = CMVideoFormatDescriptionGetDimensions(videoDevice!.activeFormat.formatDescription)
        width = Int(dim.height)
        height = Int(dim.width)

        guard let vd = videoDevice else { return } // FIXME!
        // ISO値を固定する
        let midISO = (vd.activeFormat.minISO + vd.activeFormat.maxISO) / 4
        let minDuration = vd.activeVideoMinFrameDuration
        do {
            try vd.lockForConfiguration()
            vd.setExposureModeCustom(duration: minDuration, iso: midISO, completionHandler: { (time) in
                print("setExposureModeCustom completed!")
            })
            vd.unlockForConfiguration()
        } catch {
        }
        
        // 入力（マイク）
        let audioDevice = AVCaptureDevice.default(for: AVMediaType.audio)
        let audioInput = try! AVCaptureDeviceInput.init(device: audioDevice!)
        captureSession.addInput(audioInput)

        // ビデオ処理用にキューを作る
        let videoQueue: DispatchQueue = DispatchQueue(label: "videoqueue")

        // 出力（映像）
        let videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput.setSampleBufferDelegate(self, queue: videoQueue)
        captureSession.addOutput(videoDataOutput)

        // ビデオを縦向きに
        let con = videoDataOutput.connection(with: AVMediaType.video)
        con?.videoOrientation = .portrait
        
        // 出力(音声)
        let audioDataOutput = AVCaptureAudioDataOutput()
        audioDataOutput.setSampleBufferDelegate(self, queue: videoQueue)
        captureSession.addOutput(audioDataOutput)

        
        // プレビュー
        let videoLayer = AVCaptureVideoPreviewLayer.init(session: captureSession)
        videoLayer.frame = previewView.bounds
        videoLayer.videoGravity = AVLayerVideoGravity.resize
        previewView.layer.addSublayer(videoLayer)

        // セッションの開始
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession.startRunning()
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    public func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        // ライブラリへの保存
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputFileURL)
        }) { completed, error in
            if completed {
                print("Video is saved!")
            }
        }
    }

    
    @IBAction func startCapture(_ sender: Any) {
        if isRecording { // 録画終了
            stopRecording()
            timer?.invalidate()
            timer = nil
            // flashを強制的にOFFにする
            flash = true
            toggleFlash()
        } else { // 録画開始
            timer = Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(ViewController.toggleFlash), userInfo: nil, repeats: true)
        }
        isRecording = !isRecording
    }
    
    var flash = false
    @objc func toggleFlash() {
        if !(videoDevice?.hasTorch ?? false) {
            return
        }
        do {
            try videoDevice?.lockForConfiguration()
            flash = !flash
            if (flash){
                videoDevice?.torchMode = AVCaptureDevice.TorchMode.on
            } else {
                videoDevice?.torchMode = AVCaptureDevice.TorchMode.off
            }
            videoDevice?.unlockForConfiguration()
        } catch {
            print("Torch could not be used")
        }
    }
    
    func stopRecording() {
        print("stopRecording")
        writer?.finishWriting(completionHandler: {
            print("finishWriting completed")
            self.fileOutput(self.writer!.outputURL)
        })
    }
    
    func fileOutput(_ outputFileURL: URL) {
        // ライブラリへの保存
        print("output!")
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputFileURL)
        }) { completed, error in
            if completed {
                print("Video is saved!")
            }
            self.writer = nil
            self.writing = false
        }
    }
}

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        let isVideo = output is AVCaptureVideoDataOutput
        
        if writer == nil && !isVideo  {
            // 初回音声フレームがきたら初期化する
            if let fmt = CMSampleBufferGetFormatDescription(sampleBuffer) {
                if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmt) {
                    let channels = Int(asbd.pointee.mChannelsPerFrame)
                    let samples = asbd.pointee.mSampleRate
                    initVideoWriter(width: width, height: height, channels: channels,
                                    samples: samples)
                }
            }
        }
        
        write(sampleBuffer: sampleBuffer, isVideo: isVideo)
    }
    
    func initVideoWriter(width: Int, height:Int, channels:Int, samples:Float64) {
        print("init video writer")
        let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
        let documentsDirectory = paths[0] as String
        let filePath = "\(documentsDirectory)/temp.mp4"
        let fileURL = URL(fileURLWithPath: filePath)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: filePath) {
            do {
                try fileManager.removeItem(atPath: filePath)
            } catch {
            }
        }
        
        // AVAssetWriter生成
        writer = try? AVAssetWriter(outputURL: fileURL, fileType: AVFileType.mov)
        // Video入力
        let videoOutputSettings: Dictionary<String, AnyObject> = [
            AVVideoCodecKey : AVVideoCodecType.h264 as AnyObject,
            AVVideoWidthKey : width as AnyObject,
            AVVideoHeightKey : height as AnyObject
        ];
        videoInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: videoOutputSettings)
        videoInput?.expectsMediaDataInRealTime = true
        writer?.add(videoInput!)
        
        videoInputAdapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput!, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
            ])
        
        // Audio入力
        let audioOutputSettings: Dictionary<String, AnyObject> = [
            AVFormatIDKey : kAudioFormatMPEG4AAC as AnyObject,
            AVNumberOfChannelsKey : channels as AnyObject,
            AVSampleRateKey : samples as AnyObject,
            AVEncoderBitRateKey : 128000 as AnyObject
        ]
        audioInput = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: audioOutputSettings)
        audioInput?.expectsMediaDataInRealTime = true
        writer?.add(audioInput!)
    }
    
    func write(sampleBuffer: CMSampleBuffer, isVideo: Bool) {
        if !isRecording {
            return
        }
        
        if !CMSampleBufferDataIsReady(sampleBuffer) {
            return
        }
        
        // 開始直後は音声データのみしか来ないので、最初の動画が来てから書き込みを開始する
        if isVideo && !writing {
            offsetTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer) // 開始時間を0とするために、開始時間をoffSetに保存する
            writer?.startWriting()
            print("startwriting")
            writer?.startSession(atSourceTime: kCMTimeZero) // 開始時間を0で初期化する
            writing = true
        }
        
        if !writing {
            return
        }
        
        // PTSの調整（offSetTimeだけマイナスする）
        var copyBuffer : CMSampleBuffer?
        var count: CMItemCount = 1
        var info = CMSampleTimingInfo()
        CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, count, &info, &count)
        info.presentationTimeStamp = CMTimeSubtract(info.presentationTimeStamp, offsetTime)
        CMSampleBufferCreateCopyWithNewTiming(kCFAllocatorDefault,sampleBuffer,1,&info,&copyBuffer)
        
        if isVideo {
            if (videoInput?.isReadyForMoreMediaData)! {
                
                let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
                if (flash) {
                    videoInputAdapter?.append(pixelBuffer!, withPresentationTime: info.presentationTimeStamp)
                } else {
                    // flashがOFFの時は真っ黒にする
                    
                    // let ciImage = CIImage(cvPixelBuffer: pixelBuffer!)
                    let pixelBufferWidth = CGFloat(CVPixelBufferGetWidth(pixelBuffer!))
                    let pixelBufferHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer!))
                    // let imageRect = CGRect(x: 0, y: 0, width: pixelBufferWidth, height: pixelBufferHeight)
                    // let ciContext = CIContext.init()
                    // let cgImage = ciContext.createCGImage(ciImage, from: imageRect)
                    // let image = UIImage(cgImage: cgImage!)
                    
                    // Make black UIImage
                    let size = CGSize(width: pixelBufferWidth, height: pixelBufferHeight)
                    UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
                    let context = UIGraphicsGetCurrentContext()!
                    context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
                    context.fill(CGRect(origin: .zero, size: size))
                    let image = UIGraphicsGetImageFromCurrentImageContext()!
                    UIGraphicsEndImageContext()
                    
                    // convert UIImage to CVPixelBuffer
                    let cgImage: CGImage = image.cgImage!
                    let options = [
                        kCVPixelBufferCGImageCompatibilityKey as String: true,
                        kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
                    ]
                    var pxBuffer: CVPixelBuffer? = nil
                    let width: Int = cgImage.width
                    let height: Int = cgImage.height
                    CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32ARGB, options as CFDictionary?, &pxBuffer)
                    CVPixelBufferLockBaseAddress(pxBuffer!, CVPixelBufferLockFlags(rawValue: 0))
                    let pxData: UnsafeMutableRawPointer = CVPixelBufferGetBaseAddress(pxBuffer!)!
                    let bitsPerComponent: size_t = 8
                    let bytePerRow: size_t = 4 * width
                    let rgbColorSpace: CGColorSpace = CGColorSpaceCreateDeviceRGB()
                    let _: CGContext = CGContext(data: pxData, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: bytePerRow, space: rgbColorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
                    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
                    CVPixelBufferUnlockBaseAddress(pxBuffer!, CVPixelBufferLockFlags(rawValue: 0))
                    
                    videoInputAdapter?.append(pxBuffer!, withPresentationTime: info.presentationTimeStamp)
                }
                print("append video")
            }
        } else {
            if (audioInput?.isReadyForMoreMediaData)! {
                audioInput?.append(copyBuffer!)
                print("append audio")
            }
        }
    }
}


