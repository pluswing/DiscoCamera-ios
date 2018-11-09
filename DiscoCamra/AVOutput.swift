//
//  AVOutput.swift
//  DiscoCamera
//
//  Created by pluswing on 2018/09/27.
//  Copyright © 2018年 pluswing. All rights reserved.
//

import Foundation
import AVFoundation

protocol AVOutputTransformer {
    func transform(_ buffer: CVImageBuffer) -> CVImageBuffer?
}

class AVOutput: NSObject {
    var writer: AVAssetWriter?
    
    var videoInput: AVAssetWriterInput?
    var videoInputAdapter: AVAssetWriterInputPixelBufferAdaptor?
    var audioInput: AVAssetWriterInput?

    var isRecording : Bool = false
    var writing = false

    var offsetTime = CMTime.zero
    
    var videoSize = CGSize.zero
    var transformer: AVOutputTransformer?

    func connect(_ captureSession: AVCaptureSession, videoSize: CGSize) {
        self.videoSize = videoSize

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
    }
    
    func startRecording() {
        isRecording = true
    }
    
    func stopRecording(_ callback: @escaping (URL) -> Void) {
        writer?.finishWriting(completionHandler: {
            callback(self.writer!.outputURL)
            self.writer = nil
            self.writing = false
        })
        isRecording = false
    }
}

extension AVOutput: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {

        if !isRecording {
            return
        }

        let isVideo = output is AVCaptureVideoDataOutput
        
        if writer == nil && !isVideo  {
            // 初回音声フレームがきたら初期化する
            if let fmt = CMSampleBufferGetFormatDescription(sampleBuffer) {
                if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmt) {
                    let channels = Int(asbd.pointee.mChannelsPerFrame)
                    let samples = asbd.pointee.mSampleRate
                    initVideoWriter(width: Int(self.videoSize.width), height: Int(self.videoSize.height), channels: channels,
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
                if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                    let transformed = self.transformer?.transform(pixelBuffer) ?? pixelBuffer
                    videoInputAdapter?.append(transformed, withPresentationTime:
                        info.presentationTimeStamp)
                }
            }
        } else {
            if (audioInput?.isReadyForMoreMediaData)! {
                audioInput?.append(copyBuffer!)
            }
        }
    }
}
