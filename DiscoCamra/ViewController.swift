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
    
    var captureSession = AVCaptureSession()
    var input = AVInput()
    var output = AVOutput()
        
    var timer: Timer?
    var flash = false
    var frameCounter = 0
    var lastPixelBuffer: CVPixelBuffer?

    override func viewDidLoad() {
        super.viewDidLoad()
        
        input.connect(captureSession)
        output.connect(captureSession, videoSize: input.size)
        output.transformer = self

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
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        if output.isRecording {
            output.stopRecording { (url) in }
        }
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    @IBAction func videos(_ sender: Any) {
        let next = storyboard!.instantiateViewController(withIdentifier: "videoCollectionViewController")
        self.present(next, animated: true, completion: nil)
    }
    
    @IBAction func startCapture(_ sender: Any) {
        if output.isRecording {
            output.stopRecording { (url) in
                self.fileOutput(url)
            }

            timer?.invalidate()
            timer = nil

            // flashを強制的にOFFにする
            flash = true
            toggleFlash()

        } else {
            output.startRecording()
 
            timer = Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(ViewController.toggleFlash), userInfo: nil, repeats: true)
        }
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
        }
    }

    @objc func toggleFlash() {
        input.configure { (device) in
            if !device.hasTorch { return }
            self.flash = !self.flash
            if self.flash {
                device.torchMode = .on
                self.frameCounter = 0
            } else {
                device.torchMode = .off
            }
        }
    }
}

extension ViewController: AVOutputTransformer {
    func transform(_ buffer: CVImageBuffer) -> CVImageBuffer? {
        if (flash && frameCounter == 1) {
            lastPixelBuffer = buffer
        }
        return lastPixelBuffer
    }
}

