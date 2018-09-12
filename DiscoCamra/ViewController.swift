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

class ViewController: UIViewController, AVCaptureFileOutputRecordingDelegate {
    
    @IBOutlet weak var previewView: UIView!
    
    var fileOutput: AVCaptureMovieFileOutput?
    var videoDevice: AVCaptureDevice?

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // セッションのインスタンス生成
        let captureSession = AVCaptureSession()
        
        // 入力（背面カメラ）
        videoDevice = AVCaptureDevice.default(for: AVMediaType.video)
        let videoInput = try! AVCaptureDeviceInput.init(device: videoDevice!)
        captureSession.addInput(videoInput)
        // 入力（マイク）
        let audioDevice = AVCaptureDevice.default(for: AVMediaType.audio)
        let audioInput = try! AVCaptureDeviceInput.init(device: audioDevice!)
        captureSession.addInput(audioInput)

        // 出力（動画ファイル）
        fileOutput = AVCaptureMovieFileOutput()
        captureSession.addOutput(fileOutput!)
        // プレビュー
        let videoLayer = AVCaptureVideoPreviewLayer.init(session: captureSession)
        videoLayer.frame = previewView.bounds
        videoLayer.videoGravity = AVLayerVideoGravity.resize
        previewView.layer.addSublayer(videoLayer)

        // セッションの開始
        DispatchQueue.global(qos: .userInitiated).async {
            captureSession.startRunning()
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

    var isRecording : Bool = false
    var timer: Timer?
    
    @IBAction func startCapture(_ sender: Any) {
        if isRecording { // 録画終了
            fileOutput?.stopRecording()
            timer?.invalidate()
            timer = nil
        } else { // 録画開始
            let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
            let documentsDirectory = paths[0] as String
            let filePath = "\(documentsDirectory)/temp.mp4"
            let fileURL = URL(fileURLWithPath: filePath)
            fileOutput?.startRecording(to: fileURL, recordingDelegate: self)
            
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
}

