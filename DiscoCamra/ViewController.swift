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
    var offsetTime = CMTime.zero
    
    var isRecording : Bool = false
    var timer: Timer?
    
    var lastPixelBuffer: CVPixelBuffer?
    var frameCounter = 0
    var flash = false

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
        
        if PHPhotoLibrary.authorizationStatus() != .authorized {
            PHPhotoLibrary.requestAuthorization { (status) in
                if status != .authorized {
                    self.alert("フォトライブラリーへのアクセス権限がありません。\n設定からアクセスを許可してください。", ok: { () in
                        })
                }
            }
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        writer?.finishWriting(completionHandler: {
            self.captureSession.stopRunning()
            self.writer = nil
            
            self.timer?.invalidate()
            self.timer = nil
            
            self.flash = false
            self.isRecording = false
            self.writing = false
            
            self.lastPixelBuffer = nil
            self.frameCounter = 0
        })
    }
    
    func alert(_ message: String, ok: @escaping () -> Void) {
        let alert: UIAlertController = UIAlertController(title: "ディスコカメラ", message: message, preferredStyle:  UIAlertController.Style.alert)
        
        let defaultAction: UIAlertAction = UIAlertAction(title: "OK", style: UIAlertAction.Style.default, handler:{
            // ボタンが押された時の処理を書く（クロージャ実装）
            (action: UIAlertAction!) -> Void in
            ok()
        })
        alert.addAction(defaultAction)
        present(alert, animated: true, completion: nil)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
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
    
    @objc func toggleFlash() {
        if !(videoDevice?.hasTorch ?? false) {
            return
        }
        do {
            try videoDevice?.lockForConfiguration()
            flash = !flash
            if (flash){
                videoDevice?.torchMode = AVCaptureDevice.TorchMode.on
                frameCounter = 0
            } else {
                videoDevice?.torchMode = AVCaptureDevice.TorchMode.off
            }
            videoDevice?.unlockForConfiguration()
        } catch {
            // FIXME
        }
    }
    
    func stopRecording() {
        writer?.finishWriting(completionHandler: {
            self.fileOutput(self.writer!.outputURL)
        })
    }
    
    func fileOutput(_ outputFileURL: URL) {
        // ライブラリへの保存
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputFileURL)
        }) { completed, error in
            if completed {
                self.alert("保存しました。", ok: {() in })
            } else {
                // FIXME
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
            writer?.startSession(atSourceTime: CMTime.zero) // 開始時間を0で初期化する
            writing = true
        }
        
        if !writing {
            return
        }
        
        // PTSの調整（offSetTimeだけマイナスする）
        var copyBuffer : CMSampleBuffer?
        var count: CMItemCount = 1
        var info = CMSampleTimingInfo()
        CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: count, arrayToFill: &info, entriesNeededOut: &count)
        info.presentationTimeStamp = CMTimeSubtract(info.presentationTimeStamp, offsetTime)
        CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault,sampleBuffer: sampleBuffer,sampleTimingEntryCount: 1,sampleTimingArray: &info,sampleBufferOut: &copyBuffer)
        
        if isVideo {
            if (videoInput?.isReadyForMoreMediaData)! {
                frameCounter += 1
                let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
                if (flash && frameCounter == 1) {
                    videoInputAdapter?.append(pixelBuffer!, withPresentationTime: info.presentationTimeStamp)
                    lastPixelBuffer = pixelBuffer!
                } else {
                    // flashがOFFの時はフラッシュ点灯時のピクセルバッファを使い回す＝一時停止状態
                    if lastPixelBuffer != nil {
                        videoInputAdapter?.append(lastPixelBuffer!, withPresentationTime: info.presentationTimeStamp)
                    }
                }
            }
        } else {
            if (audioInput?.isReadyForMoreMediaData)! {
                audioInput?.append(copyBuffer!)
            }
        }
    }
}
