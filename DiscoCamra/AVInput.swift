//
//  File.swift
//  DiscoCamera
//
//  Created by pluswing on 2018/09/27.
//  Copyright © 2018年 pluswing. All rights reserved.
//

import Foundation
import AVFoundation

class AVInput {
    var videoDevice: AVCaptureDevice?
    
    var size = CGSize.zero

    func connect(_ captureSession: AVCaptureSession) {
        // 入力（背面カメラ）
        videoDevice = AVCaptureDevice.default(for: AVMediaType.video)
        let videoInput = try! AVCaptureDeviceInput.init(device: videoDevice!)
        captureSession.addInput(videoInput)
        
        //　ビデオサイズを取得。
        // ビデオはデフォルトLandscape。
        // 今回はportraitで撮るので、高さと幅を逆に持っておく。
        let dim = CMVideoFormatDescriptionGetDimensions(videoDevice!.activeFormat.formatDescription)
        size.width = CGFloat(dim.height)
        size.height = CGFloat(dim.width)
        
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
    }
    
    func configure(_ callback: (AVCaptureDevice) -> Void) {
        guard let device = videoDevice else { return }
        do {
            try device.lockForConfiguration()
            callback(device)
            device.unlockForConfiguration()
        } catch {
        }
    }
}
